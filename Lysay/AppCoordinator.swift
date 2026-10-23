import AVFoundation
import Combine
import SwiftUI

/// 主 App 的总调度：本机服务、语音引擎、麦克风权限、后台保活、粘贴板同步。
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var showDictationGuide = false
    @Published var micPermission: AVAudioApplication.recordPermission
    @Published var lastError: String?
    @Published var clips: [ClipItem] {
        didSet {
            ClipStore.save(clips)
            server.broadcast(IPCEvent(type: .clips, clips: clips))
        }
    }

    let server = LocalServer()
    let engine = SpeechEngine.shared

    private var lastActivity = Date()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var booted = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        micPermission = AVAudioApplication.shared.recordPermission
        clips = ClipStore.load()
        engine.onEvent = { [weak self] e in self?.server.broadcast(e) }
        server.onCommand = { [weak self] cmd, client in self?.handle(cmd, from: client) }
        AppSettings.shared.$script
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.server.broadcast(self.engine.currentStateEvent())
            }
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
        endBackgroundTask()
    }

    /// 切到后台后多保持约 30 秒，让键盘有机会连上来同步粘贴板
    func enteredBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "lysay.sync") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
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

    private func checkKeepAlive() {
        guard engine.micRunning else { return }
        if engine.state == .listening || engine.state == .processing || engine.state == .polishing {
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
            client.send(IPCEvent(type: .clips, clips: clips))
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
        case .stop, .finish:
            engine.finishSession()
        case .cancel:
            engine.cancelSession()
        }
    }

    // MARK: - 粘贴板

    func addClip(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        clips.insert(ClipItem(text: t), at: 0)
    }

    func updateClip(_ item: ClipItem, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = clips.firstIndex(where: { $0.id == item.id }) else { return }
        if t.isEmpty {
            clips.remove(at: i)
        } else {
            clips[i].text = t
            clips[i].updatedAt = Date()
        }
    }

    func deleteClips(at offsets: IndexSet) {
        clips.remove(atOffsets: offsets)
    }

    func moveClips(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }
}
