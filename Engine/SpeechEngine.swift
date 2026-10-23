import Foundation
import Combine

/// 语音引擎：两段式识别
/// 1. 流式 Paraformer 边说边出字（partial）
/// 2. 检测到停顿（一句话说完）后，把整句音频交给 Qwen3-ASR 精修，得到带标点的最终文字（final）
final class SpeechEngine: ObservableObject {
    static let shared = SpeechEngine()

    @Published private(set) var state: IPCEvent.EngineState = .loading
    @Published private(set) var streamingReady = false
    @Published private(set) var refineReady = false
    @Published private(set) var refineLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var micRunning = false
    @Published private(set) var level: Float = 0

    /// 所有事件都在主线程回调
    var onEvent: ((IPCEvent) -> Void)?

    private let capture = AudioCapture()
    private let work = DispatchQueue(label: "lysay.asr", qos: .userInitiated)
    private let refineQueue = DispatchQueue(label: "lysay.refine", qos: .userInitiated)

    // 以下只在 work 队列访问
    private var streaming: StreamingRecognizer?
    private var listening = false
    private var preroll: [Float] = []
    private var segmentAudio: [Float] = []
    private var lastPartial = ""
    private var nextId = 0
    private var pendingRefines = 0
    private var lastLevelAt = Date.distantPast
    private var lastSpeechAt = Date()

    // 只在 refineQueue 访问
    private var refiner: RefineRecognizer?

    private init() {
        capture.onSamples = { [weak self] samples in
            self?.work.async { self?.process(samples) }
        }
        capture.onInterrupted = { [weak self] in
            self?.micRunning = false
            self?.stopListening()
        }
    }

    // MARK: - 模型

    func loadModels() {
        DispatchQueue.global(qos: .utility).async { ChineseConverter.shared.preload() }
        work.async {
            guard self.streaming == nil else { return }
            let rec = ModelPaths.streaming.flatMap { StreamingRecognizer(directory: $0, threads: 2) }
            self.streaming = rec
            DispatchQueue.main.async {
                self.streamingReady = rec != nil
                self.loadError = rec == nil ? "流式模型加载失败，请重新安装" : nil
                if rec != nil, self.state == .loading { self.setState(.ready) }
            }
        }
        if AppSettings.shared.refineEnabled { loadRefiner() }
    }

    func loadRefiner() {
        guard !refineReady, !refineLoading else { return }
        refineLoading = true
        refineQueue.async {
            if self.refiner == nil, ModelPaths.exists(ModelPaths.qwen3) {
                self.refiner = RefineRecognizer(directory: ModelPaths.qwen3!, threads: 4)
            }
            let ok = self.refiner != nil
            DispatchQueue.main.async {
                self.refineLoading = false
                self.refineReady = ok
            }
        }
    }

    func unloadRefiner() {
        refineQueue.async {
            self.refiner = nil
            DispatchQueue.main.async { self.refineReady = false }
        }
    }

    // MARK: - 麦克风

    func startMic() throws {
        guard !capture.isRunning else { micRunning = true; return }
        try capture.start()
        micRunning = true
    }

    func stopMic() {
        stopListening()
        capture.stop()
        micRunning = false
        level = 0
    }

    // MARK: - 听写

    func startListening() {
        guard streamingReady else {
            emit(IPCEvent(type: .state, state: .loading))
            return
        }
        work.async {
            guard !self.listening, let s = self.streaming else { return }
            s.reset()
            self.listening = true
            self.lastPartial = ""
            self.lastSpeechAt = Date()
            // 带上按下按钮前 0.5 秒的音频，避免吞掉第一个字
            self.segmentAudio = self.preroll
            if !self.preroll.isEmpty { s.accept(self.preroll) }
            self.preroll = []
            self.emitState(.listening)
        }
    }

    func stopListening() {
        work.async {
            guard self.listening else { return }
            self.listening = false
            self.streaming?.flush()
            self.updatePartial()
            self.finishSegment(isLast: true)
        }
    }

    func cancelListening() {
        work.async {
            guard self.listening else { return }
            self.listening = false
            self.streaming?.reset()
            self.segmentAudio = []
            self.lastPartial = ""
            self.emit(IPCEvent(type: .partial, text: ""))
            self.emitState(self.pendingRefines > 0 ? .processing : .ready)
        }
    }

    func currentStateEvent() -> IPCEvent {
        let s = AppSettings.shared.snapshot
        return IPCEvent(type: .state, state: state, script: s.script, liveCompose: s.liveCompose)
    }

    // MARK: - 识别流程（work 队列）

    private func process(_ samples: [Float]) {
        let now = Date()
        if now.timeIntervalSince(lastLevelAt) > 0.06 {
            lastLevelAt = now
            emit(IPCEvent(type: .level, level: Self.level(of: samples)))
        }

        guard listening, let s = streaming else {
            preroll.append(contentsOf: samples)
            if preroll.count > 8000 { preroll.removeFirst(preroll.count - 8000) }
            return
        }

        segmentAudio.append(contentsOf: samples)
        s.accept(samples)
        updatePartial()

        if s.isEndpoint {
            finishSegment(isLast: false)
        } else if lastPartial.isEmpty, now.timeIntervalSince(lastSpeechAt) > 30 {
            // 30 秒没说话，自动结束
            listening = false
            finishSegment(isLast: true)
        }
    }

    private func updatePartial() {
        guard let s = streaming else { return }
        let text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != lastPartial else { return }
        lastPartial = text
        if !text.isEmpty { lastSpeechAt = Date() }
        let shown = TextPostProcessor.process(text, settings: AppSettings.shared.snapshot)
        emit(IPCEvent(type: .partial, text: shown))
    }

    private func finishSegment(isLast: Bool) {
        let raw = lastPartial
        let audio = segmentAudio
        streaming?.reset()
        segmentAudio = []
        lastPartial = ""

        guard !raw.isEmpty else {
            if isLast { emitState(pendingRefines > 0 ? .processing : .ready) }
            return
        }

        nextId += 1
        let id = nextId
        pendingRefines += 1
        let settings = AppSettings.shared.snapshot
        emit(IPCEvent(type: .segment, text: TextPostProcessor.process(raw, settings: settings), id: id))
        if isLast { emitState(.processing) }

        refineQueue.async {
            var text = ""
            if settings.refineEnabled, let r = self.refiner {
                text = r.transcribe(audio)
            }
            if text.isEmpty { text = raw }
            text = TextPostProcessor.ensureEnding(text, isLast: isLast)
            let out = TextPostProcessor.process(text, settings: settings)
            self.work.async {
                self.pendingRefines -= 1
                self.emit(IPCEvent(type: .final, text: out, id: id))
                if !self.listening && self.pendingRefines == 0 {
                    self.emitState(.ready)
                }
            }
        }
    }

    // MARK: - 事件

    private func emitState(_ s: IPCEvent.EngineState) {
        let snap = AppSettings.shared.snapshot
        emit(IPCEvent(type: .state, state: s, script: snap.script, liveCompose: snap.liveCompose))
    }

    private func emit(_ event: IPCEvent) {
        DispatchQueue.main.async {
            if event.type == .state, let s = event.state { self.state = s }
            if event.type == .level { self.level = event.level ?? 0 }
            self.onEvent?(event)
        }
    }

    private func setState(_ s: IPCEvent.EngineState) {
        state = s
        onEvent?(currentStateEvent())
    }

    private static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for x in samples { sum += x * x }
        let rms = sqrt(sum / Float(samples.count))
        let db = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (db + 55) / 45))
    }
}
