import SwiftUI
import UIKit

/// 键盘的状态与逻辑。
final class KeyboardModel: ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case connecting
        case listening
        case processing
        case loading
    }

    enum Layout {
        case voice, letters, numbers, symbols
    }

    @Published var voiceState: VoiceState = .idle
    @Published var layout: Layout = .voice
    @Published var shifted = false
    @Published var capsLock = false
    @Published var script: ScriptMode
    @Published var level: Float = 0
    @Published var preview = ""          // 正在识别、还没上屏的文字
    @Published var hint: String?
    @Published var needsGlobe = true
    @Published var returnTitle = "换行"

    weak var controller: KeyboardViewController?

    private let client = IPCClient()
    private let defaults = UserDefaults.standard
    private var pending: [(id: Int, text: String)] = []
    private var partial = ""
    private var markedActive = false
    private var liveCompose = true
    private var hintTimer: Timer?

    private static let autoStartKey = "autoStartAt"

    init() {
        script = ScriptMode(rawValue: UserDefaults.standard.string(forKey: "script") ?? "") ?? .hans
        liveCompose = UserDefaults.standard.object(forKey: "liveCompose") as? Bool ?? true
        client.onEvent = { [weak self] e in self?.handle(e) }
        client.onDisconnect = { [weak self] in self?.connectionLost() }
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    // MARK: - 生命周期

    func keyboardDidAppear() {
        // 刚从 Lysay 返回：自动开始听写
        let t = defaults.double(forKey: Self.autoStartKey)
        if t > 0, Date().timeIntervalSince1970 - t < 90 {
            defaults.removeObject(forKey: Self.autoStartKey)
            startVoice(fromAutoStart: true)
        } else {
            // 预先连一下，同步简繁设置
            client.connect { [weak self] ok in
                if ok { self?.client.send(IPCCommand(cmd: .hello)) }
            }
        }
    }

    func keyboardWillDisappear() {
        if voiceState == .listening {
            client.send(IPCCommand(cmd: .stop))
        }
        commitMarkedText()
        pending.removeAll()
        partial = ""
        preview = ""
        voiceState = .idle
        client.disconnect()
    }

    // MARK: - 语音

    func micTapped() {
        haptic()
        switch voiceState {
        case .listening:
            client.send(IPCCommand(cmd: .stop))
            voiceState = .processing
        case .connecting, .processing:
            break
        case .idle, .loading:
            startVoice(fromAutoStart: false)
        }
    }

    func cancelVoice() {
        guard voiceState == .listening else { return }
        client.send(IPCCommand(cmd: .cancel))
        partial = ""
        updateComposition()
    }

    private func startVoice(fromAutoStart: Bool) {
        guard controller?.hasFullAccess == true else {
            showHint("请在 设置 › 通用 › 键盘 › 键盘 › Lysay 中开启“允许完全访问”")
            return
        }
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
        controller?.openMainApp()
        showHint("正在打开 Lysay…如未跳转，请手动打开 Lysay 后返回")
    }

    private func handle(_ e: IPCEvent) {
        switch e.type {
        case .state:
            if let s = e.script, s != script {
                script = s
                defaults.set(s.rawValue, forKey: "script")
            }
            if let c = e.liveCompose {
                liveCompose = c
                defaults.set(c, forKey: "liveCompose")
            }
            switch e.state {
            case .listening?:
                voiceState = .listening
                hint = nil
            case .processing?:
                voiceState = .processing
            case .loading?:
                voiceState = .loading
                showHint("Lysay 正在加载语音模型，请稍候")
            case .ready?:
                if voiceState != .idle && pending.isEmpty {
                    voiceState = .idle
                    level = 0
                }
            case nil:
                break
            }
        case .partial:
            partial = e.text ?? ""
            updateComposition()
        case .segment:
            if let id = e.id { pending.append((id, e.text ?? "")) }
            partial = ""
            updateComposition()
        case .final:
            commitFinal(id: e.id, text: e.text ?? "")
        case .level:
            if voiceState == .listening { level = e.level ?? 0 }
        case .needApp:
            jumpToApp()
        case .error:
            showHint(e.message ?? "出错了")
            voiceState = .idle
        }
    }

    private func connectionLost() {
        if voiceState != .idle {
            commitMarkedText()
            pending.removeAll()
            partial = ""
            preview = ""
            voiceState = .idle
            showHint("与 Lysay 的连接已断开")
        }
    }

    // MARK: - 上屏

    /// 待精修的句子 + 正在说的句子，作为“标记文本”实时显示在输入框里
    private func updateComposition() {
        let text = pending.map { $0.text }.joined() + partial
        preview = text
        guard liveCompose, let proxy else { return }
        if text.isEmpty {
            if markedActive {
                proxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                proxy.unmarkText()
                markedActive = false
            }
        } else {
            proxy.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
            markedActive = true
        }
    }

    private func commitFinal(id: Int?, text: String) {
        if let id, let idx = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: idx)
        }
        if let proxy {
            if markedActive {
                // 用精修后的文字替换标记文本并确认
                proxy.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
                proxy.unmarkText()
                markedActive = false
            } else if !text.isEmpty {
                proxy.insertText(text)
            }
        }
        updateComposition()
        if pending.isEmpty && voiceState == .processing {
            voiceState = .idle
            level = 0
        }
    }

    private func commitMarkedText() {
        if markedActive {
            proxy?.unmarkText()
            markedActive = false
        }
    }

    // MARK: - 简繁

    func toggleScript() {
        haptic()
        script = script.toggled
        defaults.set(script.rawValue, forKey: "script")
        if client.isConnected {
            client.send(IPCCommand(cmd: .setScript, script: script))
        }
        showHint(script == .hans ? "已切换为简体输出" : "已切換為繁體輸出")
    }

    // MARK: - 打字

    func insert(_ s: String) {
        if voiceState == .listening || voiceState == .processing { commitMarkedText() }
        var text = s
        if layout == .letters && (shifted || capsLock) { text = s.uppercased() }
        proxy?.insertText(text)
        if shifted && !capsLock { shifted = false }
        keyClick()
    }

    func deleteBackward() {
        if markedActive {
            // 说话过程中删除：取消当前识别
            cancelVoice()
            return
        }
        proxy?.deleteBackward()
        keyClick()
    }

    func space() {
        commitMarkedText()
        proxy?.insertText(" ")
        keyClick()
    }

    func returnKey() {
        commitMarkedText()
        proxy?.insertText("\n")
        keyClick()
    }

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
        layout = l
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
