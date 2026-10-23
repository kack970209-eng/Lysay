import Foundation
import Combine

enum TraditionalVariant: String, CaseIterable, Identifiable {
    case standard   // OpenCC 标准繁体
    case taiwan     // 台湾正体 + 台湾惯用词
    case hongkong   // 香港繁体

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "通用繁體"
        case .taiwan: return "台灣正體"
        case .hongkong: return "香港繁體"
        }
    }
}

/// 主 App 的设置。识别线程会读取，所以另外保存一份加锁的快照。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    struct Snapshot {
        var script: ScriptMode
        var variant: TraditionalVariant
        var refineEnabled: Bool
        var removeFillers: Bool
        var liveCompose: Bool
        var keepAliveMinutes: Int
    }

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var _snapshot: Snapshot

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    @Published var script: ScriptMode { didSet { save() } }
    @Published var variant: TraditionalVariant { didSet { save() } }
    @Published var refineEnabled: Bool { didSet { save() } }
    @Published var removeFillers: Bool { didSet { save() } }
    @Published var liveCompose: Bool { didSet { save() } }
    @Published var keepAliveMinutes: Int { didSet { save() } }

    private init() {
        defaults.register(defaults: [
            "script": ScriptMode.hans.rawValue,
            "variant": TraditionalVariant.standard.rawValue,
            "refineEnabled": true,
            "removeFillers": true,
            "liveCompose": true,
            "keepAliveMinutes": 5,
        ])
        let script = ScriptMode(rawValue: defaults.string(forKey: "script") ?? "") ?? .hans
        let variant = TraditionalVariant(rawValue: defaults.string(forKey: "variant") ?? "") ?? .standard
        let refine = defaults.bool(forKey: "refineEnabled")
        let fillers = defaults.bool(forKey: "removeFillers")
        let compose = defaults.bool(forKey: "liveCompose")
        let keep = defaults.integer(forKey: "keepAliveMinutes")
        self.script = script
        self.variant = variant
        self.refineEnabled = refine
        self.removeFillers = fillers
        self.liveCompose = compose
        self.keepAliveMinutes = keep
        self._snapshot = Snapshot(script: script, variant: variant, refineEnabled: refine,
                                  removeFillers: fillers, liveCompose: compose, keepAliveMinutes: keep)
    }

    private func save() {
        defaults.set(script.rawValue, forKey: "script")
        defaults.set(variant.rawValue, forKey: "variant")
        defaults.set(refineEnabled, forKey: "refineEnabled")
        defaults.set(removeFillers, forKey: "removeFillers")
        defaults.set(liveCompose, forKey: "liveCompose")
        defaults.set(keepAliveMinutes, forKey: "keepAliveMinutes")
        lock.lock()
        _snapshot = Snapshot(script: script, variant: variant, refineEnabled: refineEnabled,
                             removeFillers: removeFillers, liveCompose: liveCompose,
                             keepAliveMinutes: keepAliveMinutes)
        lock.unlock()
    }
}
