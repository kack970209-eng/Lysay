import AVFoundation
import Combine
import SwiftUI

/// 主 App 的总调度：本机服务、语音引擎、麦克风权限、后台保活、粘贴板、账号与 AI 语音额度。
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var showDictationGuide = false
    @Published var micPermission: AVAudioApplication.recordPermission
    @Published var lastError: String?
    @Published var showAccount = false
    @Published private(set) var library: ClipLibrary

    let server = LocalServer()
    let engine = SpeechEngine.shared

    private var lastActivity = Date()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var booted = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let account = AccountManager.shared
    /// 本次听写开始计时的时间（用来计算 AI 语音用量）
    private var usageTick: Date?

    private init() {
        micPermission = AVAudioApplication.shared.recordPermission
        library = ClipStore.load()
        engine.onEvent = { [weak self] e in self?.handleEngineEvent(e) }
        server.onCommand = { [weak self] cmd, client in self?.handle(cmd, from: client) }
        AppSettings.shared.$script
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.server.broadcast(self.engine.currentStateEvent())
            }
            .store(in: &cancellables)
        account.onRemoteLibrary = { [weak self] lib in
            guard let self else { return }
            self.library = lib
            self.server.broadcast(IPCEvent(type: .clips, library: lib))
        }
    }

    func boot() {
        guard !booted else { return }
        booted = true
        server.start()
        engine.loadModels()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkKeepAlive()
            self?.meterUsage()
        }
        account.loadPlans()
        account.refresh()
        account.syncNow()
    }

    func becameActive() {
        server.start()
        micPermission = AVAudioApplication.shared.recordPermission
        endBackgroundTask()
        // 键盘可能记了新的剪贴板内容
        reloadLibrary()
        account.refresh()
        account.syncNow()
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
        } else if url.host == "account" {
            showDictationGuide = false
            showAccount = true
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
            client.send(IPCEvent(type: .clips, library: library))
        case .setScript:
            if let s = cmd.script, AppSettings.shared.script != s { AppSettings.shared.script = s }
        case .start:
            if let s = cmd.script, AppSettings.shared.script != s { AppSettings.shared.script = s }
            switch account.aiAccess() {
            case .needLogin:
                client.send(IPCEvent(type: .needLogin))
                return
            case .quotaExceeded:
                client.send(IPCEvent(type: .quotaExceeded))
                return
            case .ok:
                break
            }
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
        case .syncClips:
            if let lib = cmd.library { mergeLibrary(lib) }
        }
    }

    // MARK: - 引擎事件与用量

    private func handleEngineEvent(_ e: IPCEvent) {
        server.broadcast(e)
        guard e.type == .state else { return }
        if e.state == .listening {
            if usageTick == nil { usageTick = Date() }
        } else if usageTick != nil {
            meterUsage()
            usageTick = nil
            account.flushUsage()
        }
    }

    /// 把这段时间的听写计入 AI 语音用量；免费额度用完就结束听写
    private func meterUsage() {
        guard let start = usageTick else { return }
        let now = Date()
        account.addUsage(now.timeIntervalSince(start))
        usageTick = engine.state == .listening ? now : nil
        if engine.state == .listening, account.aiAccess() == .quotaExceeded {
            engine.finishSession()
            server.broadcast(IPCEvent(type: .quotaExceeded))
        }
    }

    // MARK: - 粘贴板

    func reloadLibrary() {
        let lib = ClipStore.load()
        if lib != library { setLibrary(lib) }
    }

    private func mergeLibrary(_ other: ClipLibrary) {
        var lib = library
        lib.merge(other)
        setLibrary(lib)
    }

    /// 修改资料：存到钥匙串、通知键盘、排程云同步
    private func setLibrary(_ lib: ClipLibrary) {
        library = ClipStore.save(lib)
        server.broadcast(IPCEvent(type: .clips, library: library))
        account.scheduleSync()
    }

    private func edit(_ change: (inout ClipLibrary) -> Void) {
        var lib = ClipStore.load()
        lib.merge(library)
        change(&lib)
        setLibrary(lib)
    }

    func addFolder(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        edit { $0.folders.append(ClipFolder(name: n, sort: ($0.visibleFolders.last?.sort ?? 0) + 1)) }
    }

    func renameFolder(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        edit { lib in
            guard let i = lib.folders.firstIndex(where: { $0.id == id }) else { return }
            lib.folders[i].name = n
            lib.folders[i].updatedAt = Date()
        }
    }

    func deleteFolder(_ id: UUID) {
        edit { lib in
            let now = Date()
            for i in lib.folders.indices where lib.folders[i].id == id {
                lib.folders[i].deleted = true
                lib.folders[i].updatedAt = now
            }
            for i in lib.items.indices where lib.items[i].folderId == id && !lib.items[i].deleted {
                lib.items[i].deleted = true
                lib.items[i].updatedAt = now
            }
        }
    }

    func moveFolders(from source: IndexSet, to destination: Int) {
        edit { lib in
            var ordered = lib.visibleFolders
            ordered.move(fromOffsets: source, toOffset: destination)
            let now = Date()
            for (n, f) in ordered.enumerated() {
                if let i = lib.folders.firstIndex(where: { $0.id == f.id }) {
                    lib.folders[i].sort = Double(n)
                    lib.folders[i].updatedAt = now
                }
            }
        }
    }

    func addItem(_ text: String, to folder: UUID) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        edit { lib in
            let last = lib.items(in: folder).last?.sort ?? 0
            lib.items.append(ClipItem(folderId: folder, text: t, sort: last + 1))
        }
    }

    func updateItem(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        edit { lib in
            guard let i = lib.items.firstIndex(where: { $0.id == id }) else { return }
            if t.isEmpty {
                lib.items[i].deleted = true
            } else {
                lib.items[i].text = t
            }
            lib.items[i].updatedAt = Date()
        }
    }

    func deleteItems(_ ids: [UUID]) {
        edit { lib in
            let now = Date()
            for i in lib.items.indices where ids.contains(lib.items[i].id) {
                lib.items[i].deleted = true
                lib.items[i].updatedAt = now
            }
        }
    }

    func moveItems(in folder: UUID, from source: IndexSet, to destination: Int) {
        edit { lib in
            var ordered = lib.items(in: folder)
            ordered.move(fromOffsets: source, toOffset: destination)
            let now = Date()
            for (n, it) in ordered.enumerated() {
                if let i = lib.items.firstIndex(where: { $0.id == it.id }) {
                    lib.items[i].sort = Double(n)
                    lib.items[i].updatedAt = now
                }
            }
        }
    }

    func recordCopy(_ text: String) {
        edit { $0.recordCopy(text) }
    }

    func deleteHistory(_ ids: [UUID]) {
        edit { lib in
            let now = Date()
            for i in lib.history.indices where ids.contains(lib.history[i].id) {
                lib.history[i].deleted = true
                lib.history[i].updatedAt = now
            }
        }
    }

    func clearHistory() {
        deleteHistory(library.visibleHistory.map(\.id))
    }

    /// 把剪贴板记录收进某个文件夹
    func saveHistory(_ item: ClipHistoryItem, to folder: UUID) {
        addItem(item.text, to: folder)
    }
}
