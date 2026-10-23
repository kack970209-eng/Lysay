import AVFoundation
import Combine
import SwiftUI

/// 主 App 的总调度：本机服务、语音引擎、麦克风权限、后台保活。
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var showDictationGuide = false
    @Published var micPermission: AVAudioApplication.recordPermission
    @Published var lastError: String?

    // App 内“试一试”页面的文字
    @Published var testCommitted = ""
    @Published var testLive = ""

    let server = LocalServer()
    let engine = SpeechEngine.shared

    private var lastActivity = Date()
    private var timer: Timer?
    private var pendingSegments: [Int: String] = [:]
    private var partial = ""
    private var cancellables = Set<AnyCancellable>()
    private var booted = false

    private init() {
        micPermission = AVAudioApplication.shared.recordPermission
        engine.onEvent = { [weak self] e in self?.handleEngineEvent(e) }
        server.onCommand = { [weak self] cmd, client in self?.handle(cmd, from: client) }
        AppSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
    }

    func boot() {
        guard !booted else { return }
        booted = true
        server.start()
        engine.loadModels()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkKeepAlive()
        }
    }

    func becameActive() {
        server.start()
        micPermission = AVAudioApplication.shared.recordPermission
    }

    // MARK: - 键盘跳转

    func handle(url: URL) {
        guard url.scheme == LysayIPC.urlScheme else { return }
        if url.host == "dictate" {
            showDictationGuide = true
            ensureMic { _ in }
        }
    }

    // MARK: - 麦克风

    func ensureMic(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(startMic())
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.micPermission = AVAudioApplication.shared.recordPermission
                    completion(granted ? self.startMic() : false)
                }
            }
        default:
            micPermission = .denied
            lastError = "麦克风权限被拒绝，请在“设置 › Lysay”中开启"
            completion(false)
        }
    }

    @discardableResult
    private func startMic() -> Bool {
        do {
            try engine.startMic()
            lastActivity = Date()
            lastError = nil
            return true
        } catch {
            lastError = "麦克风启动失败：\(error.localizedDescription)"
            return false
        }
    }

    func stopMic() {
        engine.stopMic()
    }

    private func checkKeepAlive() {
        guard engine.micRunning else { return }
        if engine.state == .listening || engine.state == .processing {
            lastActivity = Date()
            return
        }
        let limit = TimeInterval(AppSettings.shared.keepAliveMinutes * 60)
        if Date().timeIntervalSince(lastActivity) > limit {
            engine.stopMic()
        }
    }

    // MARK: - 键盘命令

    private func handle(_ cmd: IPCCommand, from client: LocalServer.Client) {
        lastActivity = Date()
        switch cmd.cmd {
        case .hello:
            client.send(engine.currentStateEvent())
        case .setScript:
            if let s = cmd.script, AppSettings.shared.script != s { AppSettings.shared.script = s }
        case .start:
            if let s = cmd.script, AppSettings.shared.script != s { AppSettings.shared.script = s }
            guard engine.streamingReady else {
                client.send(IPCEvent(type: .state, state: .loading))
                return
            }
            if !engine.micRunning {
                // 后台无法重新打开麦克风，需要键盘跳转到 App
                let canStart = UIApplication.shared.applicationState == .active
                    && AVAudioApplication.shared.recordPermission == .granted
                if !canStart || !startMic() {
                    client.send(IPCEvent(type: .needApp))
                    return
                }
            }
            engine.startListening()
        case .stop:
            engine.stopListening()
        case .cancel:
            engine.cancelListening()
        }
    }

    private func settingsChanged() {
        let s = AppSettings.shared
        if s.refineEnabled { engine.loadRefiner() } else { engine.unloadRefiner() }
        server.broadcast(engine.currentStateEvent())
    }

    // MARK: - 引擎事件

    private func handleEngineEvent(_ e: IPCEvent) {
        server.broadcast(e)
        switch e.type {
        case .partial:
            partial = e.text ?? ""
        case .segment:
            if let id = e.id { pendingSegments[id] = e.text ?? "" }
            partial = ""
        case .final:
            if let id = e.id { pendingSegments.removeValue(forKey: id) }
            testCommitted += e.text ?? ""
        case .state:
            if e.state == .listening { lastActivity = Date() }
        default:
            return
        }
        testLive = pendingSegments.keys.sorted().compactMap { pendingSegments[$0] }.joined() + partial
    }

    // MARK: - App 内测试

    func toggleTestDictation() {
        if engine.state == .listening {
            engine.stopListening()
        } else {
            ensureMic { ok in
                if ok { self.engine.startListening() }
            }
        }
    }

    func clearTest() {
        testCommitted = ""
        testLive = ""
        pendingSegments = [:]
        partial = ""
    }
}
