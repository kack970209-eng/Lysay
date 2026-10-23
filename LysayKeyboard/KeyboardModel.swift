import SwiftUI
import UIKit

/// 键盘的状态与逻辑。
final class KeyboardModel: ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case connecting
        case listening
        case processing     // 等最后几句精修
        case polishing      // AI 整理中
        case loading
    }

    enum Layout: String {
        case voice, zhuyin, letters, numbers, symbols, clipboard
    }

    @Published var voiceState: VoiceState = .idle
    @Published var layout: Layout = .voice
    @Published var shifted = false
    @Published var capsLock = false
    @Published var script: ScriptMode
    @Published var level: Float = 0
    /// 说话框里显示的文字（精修过的句子 + 正在说的句子）
    @Published var voiceText = ""
    /// AI 整理中逐步生成的文字
    @Published var polishText = ""
    @Published var hint: String?
    @Published var needsGlobe = true
    @Published var returnTitle = "换行"

    // 注音
    @Published var candidates: [ZhuyinEngine.Candidate] = []
    @Published var zhuyinComposing = false
    /// 数字/符号页返回时回到哪个打字键盘（注音或英文）
    @Published var textLayout: Layout = .zhuyin

    // 粘贴板
    @Published var library = ClipLibrary()
    @Published var clipTab = 0            // 0 = 剪贴板记录，1 = 收藏
    @Published var openFolder: UUID?

    weak var controller: KeyboardViewController?

    private let client = IPCClient()
    private let defaults = UserDefaults.standard
    private var segments: [(id: Int, text: String)] = []
    private var partial = ""
    private var hintTimer: Timer?
    private let zhuyin = ZhuyinEngine()
    /// 目前以普通文字形式显示在输入框里的组字内容（注音符号 / 转换中的字）
    private var zhuyinShown = ""
    private var layoutBeforeClipboard: Layout = .voice
    private var pasteboardTimer: Timer?

    private static let autoStartKey = "autoStartAt"

    init() {
        script = ScriptMode(rawValue: UserDefaults.standard.string(forKey: "script.v2") ?? "") ?? .hant
        if let saved = UserDefaults.standard.string(forKey: "layout"), let l = Layout(rawValue: saved),
           l == .voice || l == .zhuyin || l == .letters {
            layout = l
            if l != .voice { textLayout = l }
        }
        client.onEvent = { [weak self] e in self?.handle(e) }
        client.onDisconnect = { [weak self] in self?.connectionLost() }
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    // MARK: - 生命周期

    var voiceSessionActive: Bool {
        switch voiceState {
        case .listening, .processing, .polishing: return true
        default: return false
        }
    }

    func keyboardDidAppear() {
        library = ClipStore.load()
        capturePasteboard()
        pasteboardTimer?.invalidate()
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.capturePasteboard()
        }
        // 刚从 Lysay 返回：自动开始听写
        let t = defaults.double(forKey: Self.autoStartKey)
        if t > 0, Date().timeIntervalSince1970 - t < 90 {
            defaults.removeObject(forKey: Self.autoStartKey)
            layout = .voice
            startVoice(fromAutoStart: true)
        } else {
            // 预先连一下，同步简繁设置和粘贴板
            client.connect { [weak self] ok in
                if ok { self?.client.send(IPCCommand(cmd: .hello)) }
            }
        }
    }

    func keyboardWillDisappear() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
        commitZhuyinAll()
        if voiceSessionActive {
            client.send(IPCCommand(cmd: .cancel))
        }
        resetVoice()
        client.disconnect()
    }

    // MARK: - 语音

    func micTapped() {
        commitZhuyinAll()
        haptic()
        switch voiceState {
        case .listening:
            confirmVoice()
        case .connecting, .processing, .polishing:
            break
        case .idle, .loading:
            startVoice(fromAutoStart: false)
        }
    }

    /// ✓ 讲完了：让 Lysay 做 AI 整理，整理完再上屏
    func confirmVoice() {
        guard voiceState == .listening else { return }
        haptic()
        if voiceText.isEmpty {
            cancelVoice()
            return
        }
        client.send(IPCCommand(cmd: .finish))
        voiceState = .processing
        level = 0
    }

    /// ✕ 取消这段话，什么都不输入
    func cancelVoice() {
        haptic()
        if voiceSessionActive {
            client.send(IPCCommand(cmd: .cancel))
        }
        resetVoice()
    }

    private func resetVoice() {
        segments.removeAll()
        partial = ""
        voiceText = ""
        polishText = ""
        level = 0
        voiceState = .idle
    }

    private func startVoice(fromAutoStart: Bool) {
        guard controller?.hasFullAccess == true else {
            showHint("请在 设置 › 通用 › 键盘 › 键盘 › Lysay 中开启“允许完全访问”")
            return
        }
        resetVoice()
        voiceState = .connecting
        client.connect { [weak self] ok in
            guard let self else { return }
            if ok {
                self.client.send(IPCCommand(cmd: .start, script: self.script))
            } else if fromAutoStart {
                self.voiceState = .idle
                self.showHint("Lysay 没有在后台运行，请再点一次麦克风")
            } else {
                self.jumpToApp()
            }
        }
    }

    private var lastJump = Date.distantPast

    private func jumpToApp() {
        voiceState = .idle
        // 防止权限被拒等情况下来回跳转
        guard Date().timeIntervalSince(lastJump) > 8 else {
            showHint("请打开 Lysay 检查麦克风权限")
            return
        }
        lastJump = Date()
        defaults.set(Date().timeIntervalSince1970, forKey: Self.autoStartKey)
        controller?.openMainApp(LysayIPC.dictateURL)
        showHint("正在打开 Lysay…如未跳转，请手动打开 Lysay 后返回")
    }

    private func handle(_ e: IPCEvent) {
        switch e.type {
        case .state:
            if let s = e.script, s != script {
                script = s
                defaults.set(s.rawValue, forKey: "script.v2")
            }
            switch e.state {
            case .listening?:
                if voiceState == .connecting || voiceState == .idle || voiceState == .loading {
                    voiceState = .listening
                    hint = nil
                }
            case .processing?:
                if voiceState == .listening { voiceState = .processing }
            case .polishing?:
                if voiceSessionActive { voiceState = .polishing }
            case .loading?:
                if voiceState == .connecting {
                    voiceState = .loading
                    showHint("Lysay 正在加载语音模型，请稍候")
                }
            case .ready?:
                if voiceState == .loading || voiceState == .connecting { voiceState = .idle }
            case nil:
                break
            }
        case .partial:
            guard voiceState == .listening else { return }
            partial = e.text ?? ""
            refreshVoiceText()
        case .segment:
            guard voiceSessionActive else { return }
            if let id = e.id { segments.append((id, e.text ?? "")) }
            partial = ""
            refreshVoiceText()
        case .final:
            guard voiceSessionActive else { return }
            if let id = e.id, let i = segments.firstIndex(where: { $0.id == id }) {
                segments[i].text = e.text ?? segments[i].text
            }
            refreshVoiceText()
        case .polishDelta:
            guard voiceSessionActive else { return }
            voiceState = .polishing
            polishText = e.text ?? ""
        case .polished:
            guard voiceSessionActive else { return }
            let text = e.text ?? ""
            if !text.isEmpty { proxy?.insertText(text) }
            resetVoice()
        case .level:
            if voiceState == .listening { level = e.level ?? 0 }
        case .needApp:
            jumpToApp()
        case .clips:
            if let lib = e.library {
                library.merge(lib)
                ClipStore.cacheLocally(library)
            }
        case .needLogin:
            resetVoice()
            showHint("AI 语音需要先登录 Lysay，正在打开…")
            controller?.openMainApp(LysayIPC.accountURL)
        case .quotaExceeded:
            resetVoice()
            showHint("免费 AI 语音时长已用完，升级 Pro 可无限使用")
            controller?.openMainApp(LysayIPC.accountURL)
        case .error:
            showHint(e.message ?? "出错了")
            resetVoice()
        }
    }

    private func refreshVoiceText() {
        voiceText = segments.map { $0.text }.joined() + partial
    }

    private func connectionLost() {
        if voiceState != .idle {
            resetVoice()
            showHint("与 Lysay 的连接已断开")
        }
    }

    // MARK: - 简繁

    func toggleScript() {
        haptic()
        script = script.toggled
        defaults.set(script.rawValue, forKey: "script.v2")
        if client.isConnected {
            client.send(IPCCommand(cmd: .setScript, script: script))
        }
        showHint(script == .hans ? "已切换为简体输出" : "已切換為繁體輸出")
    }

    // MARK: - 打字

    func insert(_ s: String) {
        commitZhuyinAll()
        var text = s
        if layout == .letters && (shifted || capsLock) { text = s.uppercased() }
        proxy?.insertText(text)
        if shifted && !capsLock { shifted = false }
        keyClick()
    }

    func deleteBackward() {
        if zhuyin.isComposing {
            zhuyin.backspace()
            refreshZhuyin()
            keyClick()
            return
        }
        proxy?.deleteBackward()
        keyClick()
    }

    func space() {
        if zhuyin.isComposing {
            if !zhuyin.current.isEmpty {
                // 空格 = 一声，完成当前音节
                zhuyin.inputTone(nil)
                refreshZhuyin()
            } else {
                commitZhuyinAll()
            }
            keyClick()
            return
        }
        proxy?.insertText(" ")
        keyClick()
    }

    func returnKey() {
        if zhuyin.isComposing {
            commitZhuyinAll()
            keyClick()
            return
        }
        proxy?.insertText("\n")
        keyClick()
    }

    // MARK: - 注音

    func zhuyinKey(_ key: String) {
        guard let c = key.first else { return }
        if ZhuyinEngine.isTone(c) {
            if !zhuyin.inputTone(c) && !zhuyin.isComposing {
                proxy?.insertText(key)
            }
        } else {
            zhuyin.inputSymbol(c)
        }
        refreshZhuyin()
        keyClick()
    }

    func selectCandidate(_ c: ZhuyinEngine.Candidate) {
        let text = zhuyin.select(c)
        let rest = zhuyin.displayText
        showComposition(text + rest)
        zhuyinShown = rest          // 选中的字已确定，只有后面的部分还在组字
        refreshCandidates()
        haptic()
    }

    /// 把正在组的注音整句转换后确定
    func commitZhuyinAll() {
        guard zhuyin.isComposing else { return }
        showComposition(zhuyin.commitAll())
        zhuyinShown = ""
        refreshCandidates()
    }

    private func refreshZhuyin() {
        showComposition(zhuyin.displayText)
        refreshCandidates()
    }

    private func refreshCandidates() {
        zhuyinComposing = zhuyin.isComposing
        candidates = zhuyin.candidates()
    }

    /// 组字直接写进输入框（和 iOS 原生注音一样能在输入框里看到 ㄨㄛ），
    /// 每次只删掉、补上有变化的部分。
    private func showComposition(_ new: String) {
        guard let proxy else { return }
        var old = zhuyinShown
        if !old.isEmpty, let before = proxy.documentContextBeforeInput, !before.hasSuffix(old) {
            // 光标移动或文字被宿主改动了：之前显示的内容就当作已确定，不再去删
            old = ""
        }
        let oldChars = Array(old), newChars = Array(new)
        var common = 0
        while common < oldChars.count && common < newChars.count && oldChars[common] == newChars[common] {
            common += 1
        }
        for _ in common..<oldChars.count { proxy.deleteBackward() }
        if common < newChars.count {
            proxy.insertText(String(newChars[common...]))
        }
        zhuyinShown = new
    }

    // MARK: - 粘贴板

    func toggleClipboard() {
        haptic()
        if layout == .clipboard {
            layout = layoutBeforeClipboard
            return
        }
        commitZhuyinAll()
        layoutBeforeClipboard = layout
        layout = .clipboard
        openFolder = nil
        library = ClipStore.load()
        capturePasteboard()
        // 主 App 在运行的话，顺便拿最新内容
        client.connect { [weak self] ok in
            if ok { self?.client.send(IPCCommand(cmd: .hello)) }
        }
    }

    func closeClipboard() {
        layout = layoutBeforeClipboard
        keyClick()
    }

    func insertText(_ text: String) {
        commitZhuyinAll()
        proxy?.insertText(text)
        haptic()
    }

    func pasteSystemClipboard() {
        if let text = UIPasteboard.general.string, !text.isEmpty {
            insertText(text)
        } else {
            showHint("系统剪贴板里没有文字")
        }
    }

    /// 发现系统剪贴板有新内容就记进剪贴板记录（键盘开着的时候每 2 秒看一次）
    private func capturePasteboard() {
        guard controller?.hasFullAccess == true else { return }
        let pb = UIPasteboard.general
        let count = pb.changeCount
        guard count != defaults.integer(forKey: "pasteboardChangeCount") else { return }
        defaults.set(count, forKey: "pasteboardChangeCount")
        guard pb.hasStrings, let text = pb.string, !text.isEmpty else { return }
        library.recordCopy(text)
        library = ClipStore.save(library)
        if client.isConnected {
            client.send(IPCCommand(cmd: .syncClips, library: library))
        } else {
            client.connect { [weak self] ok in
                guard let self, ok else { return }
                self.client.send(IPCCommand(cmd: .syncClips, library: self.library))
            }
        }
    }

    func deleteHistory(_ item: ClipHistoryItem) {
        if let i = library.history.firstIndex(where: { $0.id == item.id }) {
            library.history[i].deleted = true
            library.history[i].updatedAt = Date()
            library = ClipStore.save(library)
            if client.isConnected { client.send(IPCCommand(cmd: .syncClips, library: library)) }
        }
    }

    // MARK: - 键盘切换

    private var lastShiftTap = Date.distantPast

    func shiftTapped() {
        let now = Date()
        if capsLock {
            capsLock = false
            shifted = false
        } else if now.timeIntervalSince(lastShiftTap) < 0.3 {
            // 双击 shift = 大写锁定
            capsLock = true
            shifted = true
        } else {
            shifted.toggle()
        }
        lastShiftTap = now
        keyClick()
    }

    func switchLayout(_ l: Layout) {
        if l != .zhuyin { commitZhuyinAll() }
        layout = l
        if l == .zhuyin || l == .letters { textLayout = l }
        if l == .voice || l == .zhuyin || l == .letters {
            defaults.set(l.rawValue, forKey: "layout")
        }
        if l != .letters {
            shifted = false
            capsLock = false
        }
        keyClick()
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        controller?.dismissKeyboard()
    }

    // MARK: - 杂项

    func showHint(_ text: String) {
        hint = text
        hintTimer?.invalidate()
        hintTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.hint = nil
        }
    }

    private let feedback = UIImpactFeedbackGenerator(style: .light)

    private func haptic() {
        feedback.impactOccurred()
    }

    private func keyClick() {
        UIDevice.current.playInputClick()
        feedback.impactOccurred(intensity: 0.5)
    }
}
