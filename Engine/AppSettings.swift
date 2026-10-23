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
        var hotwords: [String]
    }

    let variant: TraditionalVariant = .taiwan
    let refineEnabled = true
    let removeFillers = true
    let liveCompose = true
    let keepAliveMinutes = 5

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var lockedScript: ScriptMode
    private var lockedHotwords: [String]

    /// 专有名词：让语音识别和 AI 整理保持原样（例如 Lysay）
    @Published var hotwords: [String] {
        didSet {
            defaults.set(hotwords, forKey: Self.hotwordsKey)
            lock.lock(); lockedHotwords = hotwords; lock.unlock()
        }
    }

    @Published var script: ScriptMode {
        didSet {
            defaults.set(script.rawValue, forKey: Self.scriptKey)
            lock.lock(); lockedScript = script; lock.unlock()
        }
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(script: lockedScript, variant: variant, refineEnabled: refineEnabled,
                        removeFillers: removeFillers, liveCompose: liveCompose,
                        keepAliveMinutes: keepAliveMinutes, hotwords: lockedHotwords)
    }

    private static let scriptKey = "script.v2"
    private static let hotwordsKey = "hotwords"

    private init() {
        // 默认繁体
        let s = ScriptMode(rawValue: UserDefaults.standard.string(forKey: Self.scriptKey) ?? "") ?? .hant
        lockedScript = s
        script = s
        let words = UserDefaults.standard.stringArray(forKey: Self.hotwordsKey) ?? ["Lysay"]
        lockedHotwords = words
        hotwords = words
    }
}
