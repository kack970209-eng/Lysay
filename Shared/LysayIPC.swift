import Foundation

/// 主 App 与键盘扩展之间的通信约定。
/// iOS 键盘扩展无法使用麦克风，所以录音和识别都在主 App 里进行，
/// 键盘通过本机回环地址 127.0.0.1 的 TCP 连接收发消息（每行一个 JSON）。
/// 这样不依赖 App Group，重签名后也能正常工作。
enum LysayIPC {
    static let host = "127.0.0.1"
    static let port: UInt16 = 47821
    static let urlScheme = "lysay"
    static let dictateURL = URL(string: "lysay://dictate")!
    static let accountURL = URL(string: "lysay://account")!
}

enum ScriptMode: String, Codable, CaseIterable {
    case hans   // 简体
    case hant   // 繁體

    var toggled: ScriptMode { self == .hans ? .hant : .hans }
    var shortLabel: String { self == .hans ? "简" : "繁" }
}

/// 键盘 → 主 App
struct IPCCommand: Codable {
    enum Kind: String, Codable {
        case hello, start, stop, cancel, setScript
        case finish     // 讲完了，开始 AI 整理
        case syncClips  // 键盘把粘贴板资料（含剪贴板记录）交给 App
    }
    var cmd: Kind
    var script: ScriptMode?
    var library: ClipLibrary?

    init(cmd: Kind, script: ScriptMode? = nil, library: ClipLibrary? = nil) {
        self.cmd = cmd
        self.script = script
        self.library = library
    }
}

/// 主 App → 键盘
struct IPCEvent: Codable {
    enum Kind: String, Codable {
        case state      // 引擎状态
        case partial    // 当前句子的实时识别（会不断变化）
        case segment    // 一句话说完，原始文字，等待精修
        case final      // 精修后的句子（显示在键盘的说话框里）
        case polishDelta // AI 整理进行中的文字
        case polished   // AI 整理完成，可以上屏
        case level      // 音量，用于动画
        case needApp    // 需要跳到主 App 开启麦克风
        case clips      // 粘贴板内容同步
        case needLogin  // AI 语音需要先登录
        case quotaExceeded // 免费额度用完，需要 Pro
        case error
    }

    enum EngineState: String, Codable {
        case loading, ready, listening, processing, polishing
    }

    var type: Kind
    var state: EngineState?
    var text: String?
    var id: Int?
    var level: Float?
    var script: ScriptMode?
    var liveCompose: Bool?
    var message: String?
    var library: ClipLibrary?

    init(type: Kind, state: EngineState? = nil, text: String? = nil, id: Int? = nil,
         level: Float? = nil, script: ScriptMode? = nil, liveCompose: Bool? = nil, message: String? = nil,
         library: ClipLibrary? = nil) {
        self.type = type
        self.state = state
        self.text = text
        self.id = id
        self.level = level
        self.script = script
        self.liveCompose = liveCompose
        self.message = message
        self.library = library
    }
}

enum LineCodec {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    /// 从缓冲区中取出所有完整的行，剩余的不完整部分留在 buffer 里。
    static func drainLines(_ buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
