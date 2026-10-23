import Foundation
import Security

// MARK: - 数据

/// 收藏文件夹
struct ClipFolder: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var sort: Double
    var updatedAt: Date
    var deleted: Bool

    init(id: UUID = UUID(), name: String, sort: Double = Date().timeIntervalSince1970,
         updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.name = name
        self.sort = sort
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

/// 文件夹里保存的一段文字
struct ClipItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var folderId: UUID?
    var text: String
    var sort: Double
    var updatedAt: Date
    var deleted: Bool

    init(id: UUID = UUID(), folderId: UUID?, text: String, sort: Double = Date().timeIntervalSince1970,
         updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.folderId = folderId
        self.text = text
        self.sort = sort
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    // 兼容旧版本（只有 id、text、updatedAt）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        sort = try c.decodeIfPresent(Double.self, forKey: .sort) ?? updatedAt.timeIntervalSince1970
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
}

/// 剪贴板记录：复制过的文字
struct ClipHistoryItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

/// 整个粘贴板资料库。删除用 deleted 标记（方便多端同步），定期清理。
struct ClipLibrary: Codable, Equatable {
    var folders: [ClipFolder] = []
    var items: [ClipItem] = []
    var history: [ClipHistoryItem] = []

    static let historyLimit = 100

    var visibleFolders: [ClipFolder] { folders.filter { !$0.deleted }.sorted { $0.sort < $1.sort } }
    var visibleHistory: [ClipHistoryItem] { history.filter { !$0.deleted }.sorted { $0.createdAt > $1.createdAt } }

    func items(in folder: UUID) -> [ClipItem] {
        items.filter { !$0.deleted && $0.folderId == folder }.sorted { $0.sort < $1.sort }
    }

    /// 合并另一份资料：同一 ID 以较新的为准
    mutating func merge(_ other: ClipLibrary) {
        folders = Self.mergeList(folders, other.folders, id: \.id, date: \.updatedAt)
        items = Self.mergeList(items, other.items, id: \.id, date: \.updatedAt)
        history = Self.mergeList(history, other.history, id: \.id, date: \.updatedAt)
        trim()
    }

    /// 记一条复制内容；同样的文字只留最新一条
    mutating func recordCopy(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let now = Date()
        if let i = history.firstIndex(where: { !$0.deleted && $0.text == text }) {
            history[i].createdAt = now
            history[i].updatedAt = now
        } else {
            history.append(ClipHistoryItem(text: text))
        }
        trim()
    }

    /// 历史最多保留 100 条；删除标记保留 30 天供同步
    mutating func trim() {
        let alive = visibleHistory
        if alive.count > Self.historyLimit {
            let drop = Set(alive.dropFirst(Self.historyLimit).map(\.id))
            let now = Date()
            for i in history.indices where drop.contains(history[i].id) {
                history[i].deleted = true
                history[i].updatedAt = now
            }
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        history.removeAll { $0.deleted && $0.updatedAt < cutoff }
        items.removeAll { $0.deleted && $0.updatedAt < cutoff }
        folders.removeAll { $0.deleted && $0.updatedAt < cutoff }
    }

    private static func mergeList<T>(_ a: [T], _ b: [T], id: KeyPath<T, UUID>, date: KeyPath<T, Date>) -> [T] {
        var map: [UUID: T] = [:]
        for x in a { map[x[keyPath: id]] = x }
        for x in b {
            if let cur = map[x[keyPath: id]], cur[keyPath: date] >= x[keyPath: date] { continue }
            map[x[keyPath: id]] = x
        }
        return Array(map.values)
    }
}

// MARK: - 存取

/// 粘贴板资料的存取。
/// 主 App 与键盘之间优先通过共享钥匙串传递（团队 ID 前缀 + com.lysay.shared）；
/// 不可用时退回各自的本地缓存，再靠本机连接同步。
enum ClipStore {
    private static let localKey = "clipLibrary.v2"
    private static let service = "com.lysay.clips"
    private static let account = "library.v2"
    private static let legacyAccount = "items"
    private static let legacyLocalKey = "clipItems"

    /// 读取：钥匙串与本地缓存合并
    static func load() -> ClipLibrary {
        var lib = loadLocal()
        if let data = readKeychain(account), let shared = try? decoder.decode(ClipLibrary.self, from: data) {
            lib.merge(shared)
        }
        migrateLegacy(into: &lib)
        return lib
    }

    /// 写入前先和已存的内容合并，避免键盘和 App 互相覆盖
    @discardableResult
    static func save(_ lib: ClipLibrary) -> ClipLibrary {
        var merged = lib
        if let data = readKeychain(account), let shared = try? decoder.decode(ClipLibrary.self, from: data) {
            merged.merge(shared)
        }
        cacheLocally(merged)
        if let data = try? encoder.encode(merged) {
            writeKeychain(account, data)
        }
        return merged
    }

    static func loadLocal() -> ClipLibrary {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let lib = try? decoder.decode(ClipLibrary.self, from: data) else { return ClipLibrary() }
        return lib
    }

    static func cacheLocally(_ lib: ClipLibrary) {
        if let data = try? encoder.encode(lib) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    static var sharedKeychainAvailable: Bool { sharedGroup != nil }

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

    /// 旧版本只有一个平铺的列表，搬进“常用”文件夹
    private static func migrateLegacy(into lib: inout ClipLibrary) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "clipMigrated.v2") else { return }
        defaults.set(true, forKey: "clipMigrated.v2")
        var old: [ClipItem] = []
        let legacyDecoder = JSONDecoder()
        if let data = readKeychain(legacyAccount), let items = try? legacyDecoder.decode([ClipItem].self, from: data) {
            old = items
        } else if let data = defaults.data(forKey: legacyLocalKey),
                  let items = try? legacyDecoder.decode([ClipItem].self, from: data) {
            old = items
        }
        guard !old.isEmpty, !lib.items.contains(where: { o in old.contains { $0.id == o.id } }) else { return }
        let folder = ClipFolder(name: "常用", sort: 0)
        lib.folders.append(folder)
        for (i, var item) in old.enumerated() {
            item.folderId = folder.id
            item.sort = Double(i)
            item.updatedAt = Date()
            lib.items.append(item)
        }
        save(lib)
    }

    // MARK: 钥匙串

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

    static let sharedGroup: String? = {
        guard let prefix = teamPrefix else { return nil }
        let group = "\(prefix).com.lysay.shared"
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.lysay.probe",
            kSecAttrAccount as String: "shared-probe",
            kSecAttrAccessGroup as String: group,
        ]
        if SecItemCopyMatching(probe as CFDictionary, nil) == errSecSuccess { return group }
        var add = probe
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        return (status == errSecSuccess || status == errSecDuplicateItem) ? group : nil
    }()

    private static func itemQuery(_ group: String, _ account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    static func readKeychain(_ account: String, service: String = ClipStore.service) -> Data? {
        guard let group = sharedGroup else { return nil }
        var q = itemQuery(group, account, service: service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func writeKeychain(_ account: String, _ data: Data?, service: String = ClipStore.service) {
        guard let group = sharedGroup else { return }
        let q = itemQuery(group, account, service: service)
        guard let data else {
            SecItemDelete(q as CFDictionary)
            return
        }
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
