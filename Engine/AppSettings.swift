import Foundation
import Combine

enum TraditionalVariant: String {
    case standard   // OpenCC 标准繁体
    case taiwan     // 台湾正体 + 台湾惯用词
    case hongkong   // 香港繁体
}

/// 主 App 的设置。设置界面已精简，只剩简繁由键盘切换并同步过来，其他都是固定值：
/// Qwen3 精修、去语气词、实时上屏都默认开启，后台保持麦克风 5 分钟，繁体用台湾正体。
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

    let variant: TraditionalVariant = .taiwan
    let refineEnabled = true
    let removeFillers = true
    let liveCompose = true
    let keepAliveMinutes = 5

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var _script: ScriptMode

    @Published var script: ScriptMode {
        didSet {
            defaults.set(script.rawValue, forKey: Self.scriptKey)
            lock.lock(); _script = script; lock.unlock()
        }
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(script: _script, variant: variant, refineEnabled: refineEnabled,
                        removeFillers: removeFillers, liveCompose: liveCompose,
                        keepAliveMinutes: keepAliveMinutes)
    }

    private static let scriptKey = "script.v2"

    private init() {
        // 默认繁体
        let s = ScriptMode(rawValue: defaults.string(forKey: Self.scriptKey) ?? "") ?? .hant
        _script = s
        script = s
    }
}
