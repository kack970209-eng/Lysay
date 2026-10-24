import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// 账号：Apple / Google 登录、AI 语音额度与 Pro、粘贴板云同步。
/// 服务器是 Cloudflare Worker（Info.plist 的 LysayAPIBase）。
final class AccountManager: NSObject, ObservableObject {
    static let shared = AccountManager()

    struct Profile: Codable, Equatable {
        struct User: Codable, Equatable {
            var id: String
            var email: String?
            var name: String?
            var provider: String
        }
        struct Plan: Codable, Equatable {
            var id: String
            var name: String
            var expiresAt: Double
        }
        struct AI: Codable, Equatable {
            var pro: Bool
            var freeSeconds: Int
            var usedSeconds: Int
            var remainingSeconds: Int   // Pro 为 -1
        }
        var user: User
        var plan: Plan?
        var ai: AI
    }

    struct PlanInfo: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var price: Int
        var currency: String
        var days: Int
    }

    enum AIAccess {
        case ok
        case needLogin
        case quotaExceeded
    }

    @Published private(set) var profile: Profile?
    @Published private(set) var plans: [PlanInfo] = []
    @Published var busy = false
    @Published var errorMessage: String?
    @Published private(set) var lastSyncAt: Date?
    /// 还没上传的 AI 语音秒数
    @Published private(set) var pendingUsage: Double

    /// 云同步拿到新资料后回调（主线程）
    var onRemoteLibrary: ((ClipLibrary) -> Void)?

    private let defaults = UserDefaults.standard
    private var token: String?
    private var webSession: ASWebAuthenticationSession?
    private var syncTask: Task<Void, Never>?

    static let apiBase: URL = {
        let s = Bundle.main.object(forInfoDictionaryKey: "LysayAPIBase") as? String ?? ""
        return URL(string: s.isEmpty ? "https://lysay-api.kack970209.workers.dev" : s)!
    }()

    static var googleClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LysayGoogleClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }

    var isLoggedIn: Bool { token != nil && profile != nil }

    private override init() {
        pendingUsage = UserDefaults.standard.double(forKey: "pendingUsage")
        super.init()
        token = Self.readToken()
        if let data = defaults.data(forKey: "profile"), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p
        }
        if let t = defaults.object(forKey: "lastSyncAt") as? Double { lastSyncAt = Date(timeIntervalSince1970: t) }
    }

    // MARK: - AI 语音额度

    /// 剩余免费秒数（扣掉还没上传的用量）；Pro 返回 nil
    var remainingFreeSeconds: Double? {
        guard let p = profile else { return 0 }
        if p.ai.pro { return nil }
        return max(0, Double(p.ai.remainingSeconds) - pendingUsage)
    }

    func aiAccess() -> AIAccess {
        guard isLoggedIn, let p = profile else { return .needLogin }
        if p.ai.pro { return .ok }
        return (remainingFreeSeconds ?? 0) > 0 ? .ok : .quotaExceeded
    }

    func addUsage(_ seconds: Double) {
        guard seconds > 0, isLoggedIn else { return }
        pendingUsage += seconds
        defaults.set(pendingUsage, forKey: "pendingUsage")
    }

    /// 把用量传给服务器（顺便刷新套餐状态）
    func flushUsage() {
        guard isLoggedIn else { return }
        let seconds = Int(pendingUsage.rounded(.down))
        Task {
            do {
                let p: Profile
                if seconds > 0 {
                    p = try await request("/v1/usage", method: "POST", body: ["seconds": seconds])
                } else {
                    p = try await request("/v1/me")
                }
                await MainActor.run {
                    self.pendingUsage = max(0, self.pendingUsage - Double(seconds))
                    self.defaults.set(self.pendingUsage, forKey: "pendingUsage")
                    self.setProfile(p)
                }
            } catch {
                // 离线时下次再传
            }
        }
    }

    func loadPlans() {
        Task {
            struct R: Decodable { var plans: [PlanInfo] }
            if let r: R = try? await request("/v1/plans", auth: false) {
                await MainActor.run { self.plans = r.plans }
            }
        }
    }

    // MARK: - 登录

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Apple 登录失败：\(error.localizedDescription)"
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let idToken = String(data: data, encoding: .utf8) else {
                errorMessage = "Apple 登录失败：没有拿到身份令牌"
                return
            }
            let name = [cred.fullName?.familyName, cred.fullName?.givenName]
                .compactMap { $0 }.joined()
            var body: [String: Any] = ["identityToken": idToken]
            if !name.isEmpty { body["fullName"] = name }
            finishLogin(path: "/v1/auth/apple", body: body)
        }
    }

    func signInWithGoogle() {
        let clientID = Self.googleClientID
        guard !clientID.isEmpty else {
            errorMessage = "Google 登录尚未设定（缺少 Google 客户端 ID）"
            return
        }
        // iOS 类型客户端的回调 scheme：把 client ID 倒过来
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomString(24)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { [weak self] url, error in
            guard let self else { return }
            if let error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                DispatchQueue.main.async { self.errorMessage = "Google 登录失败：\(error.localizedDescription)" }
                return
            }
            guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async { self.errorMessage = "Google 登录失败：回调参数不正确" }
                return
            }
            Task { await self.exchangeGoogle(code: code, verifier: verifier, clientID: clientID, redirect: redirect) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        session.start()
    }

    private func exchangeGoogle(code: String, verifier: String, clientID: String, redirect: String) async {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        let form = [
            "code": code, "client_id": clientID, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ]
        req.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = obj["id_token"] as? String else {
                await MainActor.run { self.errorMessage = "Google 登录失败：没有拿到身份令牌" }
                return
            }
            await MainActor.run { self.finishLogin(path: "/v1/auth/google", body: ["idToken": idToken]) }
        } catch {
            await MainActor.run { self.errorMessage = "Google 登录失败：\(error.localizedDescription)" }
        }
    }

    private func finishLogin(path: String, body: [String: Any]) {
        busy = true
        errorMessage = nil
        Task {
            struct LoginResponse: Decodable {
                var token: String
                var user: Profile.User
                var plan: Profile.Plan?
                var ai: Profile.AI
            }
            do {
                let r: LoginResponse = try await request(path, method: "POST", body: body, auth: false)
                await MainActor.run {
                    self.token = r.token
                    Self.saveToken(r.token)
                    self.setProfile(Profile(user: r.user, plan: r.plan, ai: r.ai))
                    self.busy = false
                    self.syncNow()
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.errorMessage = "登录失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func signOut() {
        token = nil
        Self.saveToken(nil)
        profile = nil
        defaults.removeObject(forKey: "profile")
        defaults.removeObject(forKey: "lastSyncAt")
        lastSyncAt = nil
        pendingUsage = 0
        defaults.set(0, forKey: "pendingUsage")
    }

    func deleteAccount() {
        Task {
            struct Ok: Decodable { var ok: Bool }
            do {
                let _: Ok = try await request("/v1/account", method: "DELETE")
                await MainActor.run { self.signOut() }
            } catch {
                await MainActor.run { self.errorMessage = "删除失败：\(error.localizedDescription)" }
            }
        }
    }

    /// 把 Apple 签名的交易交给服务器验证并开通 Pro
    func verifyTransactions(_ jws: [String]) async {
        guard isLoggedIn, !jws.isEmpty else { return }
        do {
            let p: Profile = try await request("/v1/iap/verify", method: "POST", body: ["signedTransactions": jws])
            await MainActor.run { self.setProfile(p) }
        } catch {
            await MainActor.run { self.errorMessage = "订阅验证失败：\(error.localizedDescription)" }
        }
    }

    func refresh() {
        guard isLoggedIn else { return }
        flushUsage()
    }

    private func setProfile(_ p: Profile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: "profile") }
    }

    // MARK: - 粘贴板云同步

    /// 稍后同步（合并短时间内的多次修改）
    func scheduleSync() {
        guard isLoggedIn else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    func syncNow() {
        guard isLoggedIn else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in await self?.performSync() }
    }

    private func performSync() async {
        let local = ClipStore.load()
        let since = (lastSyncAt?.timeIntervalSince1970 ?? 0) * 1000
        struct SyncBody: Encodable {
            var since: Double
            var folders: [ClipFolder]
            var items: [ClipItem]
            var history: [ClipHistoryItem]
        }
        struct SyncResponse: Decodable {
            var serverTime: Double
            var folders: [ClipFolder]
            var items: [ClipItem]
            var history: [ClipHistoryItem]
        }
        // 只上传上次同步后改过的
        let cutoff = lastSyncAt ?? .distantPast
        let body = SyncBody(
            since: since,
            folders: local.folders.filter { $0.updatedAt > cutoff },
            items: local.items.filter { $0.updatedAt > cutoff },
            history: local.history.filter { $0.updatedAt > cutoff })
        do {
            let r: SyncResponse = try await request("/v1/sync", method: "POST", encodable: body)
            var remote = ClipLibrary()
            remote.folders = r.folders
            remote.items = r.items
            remote.history = r.history
            var merged = ClipStore.load()
            merged.merge(remote)
            merged = ClipStore.save(merged)
            await MainActor.run {
                self.lastSyncAt = Date(timeIntervalSince1970: r.serverTime / 1000)
                self.defaults.set(r.serverTime / 1000, forKey: "lastSyncAt")
                self.onRemoteLibrary?(merged)
            }
        } catch {
            // 网络不通时下次再同步
        }
    }

    // MARK: - 网络

    private struct APIError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                                       auth: Bool = true) async throws -> T {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await send(path, method: method, data: data, auth: auth)
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String, encodable: B) async throws -> T {
        try await send(path, method: method, data: try Self.encoder.encode(encodable), auth: true)
    }

    private func send<T: Decodable>(_ path: String, method: String, data: Data?, auth: Bool) async throws -> T {
        var req = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        req.httpBody = data
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && auth {
            await MainActor.run { self.signOut() }
        }
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["error"] as? String
            throw APIError(message: msg ?? "服务器错误（\(status)）")
        }
        return try Self.decoder.decode(T.self, from: respData)
    }

    // MARK: - 令牌保存（只在本 App 的钥匙串）

    private static let tokenService = "com.lysay.auth"

    private static func readToken() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: "session",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String?) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: "session",
        ]
        SecItemDelete(q as CFDictionary)
        guard let token else { return }
        var add = q
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - 工具

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

extension AccountManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
