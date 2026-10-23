import Foundation
import SherpaOnnxC

/// 内置模型在 App 包里的位置（由构建脚本放进 Models/ 目录）。
enum ModelPaths {
    static var root: URL? { Bundle.main.url(forResource: "Models", withExtension: nil) }

    /// 流式模型：阿里 Paraformer 中英双语流式版（int8）
    static var streaming: URL? { root?.appendingPathComponent("streaming", isDirectory: true) }

    /// 精修模型：Qwen3-ASR-0.6B（int8）
    static var qwen3: URL? { root?.appendingPathComponent("qwen3", isDirectory: true) }

    /// AI 整理：Qwen3-0.6B（GGUF Q8_0，llama.cpp）
    static var polisher: URL? {
        guard let url = root?.appendingPathComponent("llm/qwen3-0.6b-q8_0.gguf"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func exists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

/// 流式识别：边说边出字，并通过端点检测判断一句话是否说完。
final class StreamingRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer

    init?(directory dir: URL, threads: Int = 2) {
        let encoder = dir.appendingPathComponent("encoder.int8.onnx").path
        let decoder = dir.appendingPathComponent("decoder.int8.onnx").path
        let tokens = dir.appendingPathComponent("tokens.txt").path
        guard FileManager.default.fileExists(atPath: encoder),
              FileManager.default.fileExists(atPath: decoder),
              FileManager.default.fileExists(atPath: tokens) else { return nil }

        var created: OpaquePointer?
        autoreleasepool {
            let paraformer = sherpaOnnxOnlineParaformerModelConfig(encoder: encoder, decoder: decoder)
            let model = sherpaOnnxOnlineModelConfig(tokens: tokens, paraformer: paraformer,
                                                    numThreads: threads, provider: "cpu")
            var config = sherpaOnnxOnlineRecognizerConfig(
                featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80),
                modelConfig: model,
                enableEndpoint: true,
                rule1MinTrailingSilence: 2.4,   // 一直没说话
                rule2MinTrailingSilence: 0.8,   // 说完后停顿 0.8 秒算一句
                rule3MinUtteranceLength: 20     // 单句最长 20 秒
            )
            created = SherpaOnnxCreateOnlineRecognizer(&config)
        }
        guard let rec = created, let s = SherpaOnnxCreateOnlineStream(rec) else { return nil }
        recognizer = rec
        stream = s
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func accept(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { buf in
            SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, buf.baseAddress, Int32(buf.count))
        }
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
    }

    var text: String {
        guard let r = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { return "" }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(r) }
        guard let c = r.pointee.text else { return "" }
        return String(cString: c)
    }

    var isEndpoint: Bool { SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0 }

    func reset() { SherpaOnnxOnlineStreamReset(recognizer, stream) }

    /// 停止时补一小段静音，把最后几个字“冲”出来。
    func flush() {
        accept([Float](repeating: 0, count: 8000))
    }
}

/// 精修识别：一句话说完后，用 Qwen3-ASR 对整句音频重新识别，带标点、纠错更准。
final class RefineRecognizer {
    private let recognizer: OpaquePointer

    init?(directory dir: URL, threads: Int = 4) {
        let conv = dir.appendingPathComponent("conv_frontend.onnx").path
        let encoder = dir.appendingPathComponent("encoder.int8.onnx").path
        let decoder = dir.appendingPathComponent("decoder.int8.onnx").path
        let tokenizer = dir.appendingPathComponent("tokenizer", isDirectory: true).path
        for p in [conv, encoder, decoder, tokenizer] where !FileManager.default.fileExists(atPath: p) {
            NSLog("[Lysay] Qwen3 文件缺失: \(p)")
            return nil
        }

        var created: OpaquePointer?
        autoreleasepool {
            let qwen = sherpaOnnxOfflineQwen3ASRModelConfig(
                convFrontend: conv, encoder: encoder, decoder: decoder, tokenizer: tokenizer,
                maxTotalLen: 1024, maxNewTokens: 256, temperature: 1e-6, topP: 0.8, seed: 42, hotwords: "")
            let model = sherpaOnnxOfflineModelConfig(tokens: "", numThreads: threads, provider: "cpu",
                                                     debug: 0, qwen3Asr: qwen)
            var config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80),
                modelConfig: model)
            created = SherpaOnnxCreateOfflineRecognizer(&config)
        }
        guard let rec = created else { return nil }
        recognizer = rec
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    /// hotwords：逗号分隔的专有名词，帮助模型认出 “Lysay” 这类词
    func transcribe(_ samples: [Float], hotwords: String = "") -> String {
        guard samples.count > 4800, let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        if !hotwords.isEmpty {
            SherpaOnnxOfflineStreamSetOption(stream, "hotwords", hotwords)
        }
        samples.withUnsafeBufferPointer { buf in
            SherpaOnnxAcceptWaveformOffline(stream, 16000, buf.baseAddress, Int32(buf.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let r = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(r) }
        guard let c = r.pointee.text else { return "" }
        return String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
