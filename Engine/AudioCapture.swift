import AVFoundation

/// 麦克风采集，统一转换成 16kHz 单声道 Float。
final class AudioCapture {
    var onSamples: (([Float]) -> Void)?
    var onInterrupted: (() -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                       channels: 1, interleaved: false)!
    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began, self.isRunning {
                self.stop()
                self.onInterrupted?()
            }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                                        object: engine, queue: .main) { [weak self] _ in
            // 耳机插拔等导致格式变化，重新挂载采集
            guard let self, self.isRunning else { return }
            self.stop()
            try? self.start()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Lysay", code: 1, userInfo: [NSLocalizedDescriptionKey: "麦克风不可用"])
        }
        converter = AVAudioConverter(from: format, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let ch = out.floatChannelData else { return }
        onSamples?(Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))))
    }
}
