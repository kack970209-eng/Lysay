import Foundation
import Security

/// 粘贴板里保存的一条内容
struct ClipItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), text: String, updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// 粘贴板内容的存取。
/// 主 App 与键盘之间优先通过共享钥匙串传递（团队 ID 前缀 + com.lysay.shared），
/// 重签名后若没有共享钥匙串权限，就退回各自的本地缓存，再靠本机连接同步。
enum ClipStore {
    private static let localKey = "clipItems"
    private static let service = "com.lysay.clips"
    private static let account = "items"

    static func load() -> [ClipItem] {
        if let data = readKeychain(), let items = try? JSONDecoder().decode([ClipItem].self, from: data) {
            cacheLocally(items)
            return items
        }
        return loadLocal()
    }

    static func save(_ items: [ClipItem]) {
        cacheLocally(items)
        if let data = try? JSONEncoder().encode(items) {
            writeKeychain(data)
        }
    }

    static func loadLocal() -> [ClipItem] {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data) else { return [] }
        return items
    }

    static func cacheLocally(_ items: [ClipItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    /// 是否能用共享钥匙串（用于界面提示）
    static var sharedKeychainAvailable: Bool { sharedGroup != nil }

    // MARK: - 钥匙串

    /// 取得签名证书的团队 ID：先存一个探测项，再读回它的 access group（格式 “TEAMID.bundleid”）
    private static let teamPrefix: String? = {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.lysay.probe",
            kSecAttrAccount as String: "probe",
        ]
        var query = base
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = Data()
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecReturnAttributes as String] = true
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first else { return nil }
        return String(prefix)
    }()

    private static let sharedGroup: String? = {
        guard let prefix = teamPrefix else { return nil }
        let group = "\(prefix).com.lysay.shared"
        // 试写一次，确认这个分组可用
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.lysay.probe",
            kSecAttrAccount as String: "shared-probe",
            kSecAttrAccessGroup as String: group,
        ]
        var check = probe
        check[kSecReturnData as String] = false
        if SecItemCopyMatching(check as CFDictionary, nil) == errSecSuccess { return group }
        var add = probe
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        return (status == errSecSuccess || status == errSecDuplicateItem) ? group : nil
    }()

    private static func itemQuery(_ group: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    private static func readKeychain() -> Data? {
        guard let group = sharedGroup else { return nil }
        var q = itemQuery(group)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeKeychain(_ data: Data) {
        guard let group = sharedGroup else { return }
        let q = itemQuery(group)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
