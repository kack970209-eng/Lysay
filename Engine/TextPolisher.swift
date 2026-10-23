import Foundation
import llama

/// AI 整理：用本地小模型（Qwen3-0.6B，llama.cpp）把整段口语整理成通顺的书面文字。
/// 主 App 在后台运行时 iOS 不允许用 GPU，所以只用 CPU 推理。
final class TextPolisher {
    static let systemPrompt = """
    你是语音输入法的文字整理助手。用户会给你一段语音识别出来的口语文字，请把它整理成通顺、简洁的一段话：
    1. 删除口头禅和语气词，例如：嗯、啊、呃、那个、就是说、然后呢。
    2. 删除结巴和重复的字词，例如“我我我想”整理成“我想”。
    3. 说话中途改口时，只保留改口后的内容。
    4. 修正明显的同音错别字，补全标点，合理分句。
    5. 英文单词、品牌名、人名保持英文原样，不要翻译成中文，也不要把中文改写成英文。
    6. 不要添加原文没有的信息，不要回答或评论内容，不要改变原意和人称。
    只输出整理后的文字，不要任何解释。
    """

    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let nBatch: Int32 = 512

    private static let cpuDevices: UnsafeMutablePointer<ggml_backend_dev_t?> = {
        let p = UnsafeMutablePointer<ggml_backend_dev_t?>.allocate(capacity: 2)
        p[0] = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU)
        p[1] = nil
        return p
    }()

    init?(modelURL: URL, threads: Int32 = 4) {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 0
        mp.load_mode = LLAMA_LOAD_MODE_MMAP
        if Self.cpuDevices[0] != nil { mp.devices = Self.cpuDevices }
        guard let m = llama_model_load_from_file(modelURL.path, mp) else {
            NSLog("[Lysay] 整理模型加载失败")
            return nil
        }

        var cp = llama_context_default_params()
        cp.n_ctx = 2048
        cp.n_batch = UInt32(nBatch)
        cp.n_threads = threads
        cp.n_threads_batch = threads
        cp.offload_kqv = false
        cp.op_offload = false
        cp.no_perf = true
        guard let c = llama_init_from_model(m, cp), let v = llama_model_get_vocab(m) else {
            llama_model_free(m)
            return nil
        }
        model = m
        ctx = c
        vocab = v
    }

    deinit {
        llama_free(ctx)
        llama_model_free(model)
    }

    /// 整理一段文字；onPartial 会随生成进度不断回调（已生成的全部文字）。
    /// 失败或结果异常时返回 nil，由调用方退回规则清理。
    func polish(_ text: String, hotwords: [String] = [], onPartial: (String) -> Void) -> String? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= 1200 else { return nil }

        llama_memory_clear(llama_get_memory(ctx), true)

        var system = Self.systemPrompt
        if !hotwords.isEmpty {
            system += "\n以下专有名词必须原样保留：" + hotwords.joined(separator: "、")
        }
        let prompt = "<|im_start|>system\n\(system)<|im_end|>\n"
            + "<|im_start|>user\n\(input)<|im_end|>\n"
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        var tokens = tokenize(prompt)
        guard !tokens.isEmpty, tokens.count < 1500 else { return nil }

        // 处理提示词
        var offset = 0
        while offset < tokens.count {
            let n = min(Int(nBatch), tokens.count - offset)
            let rc = tokens.withUnsafeMutableBufferPointer { buf -> Int32 in
                let batch = llama_batch_get_one(buf.baseAddress! + offset, Int32(n))
                return llama_decode(ctx, batch)
            }
            guard rc == 0 else { return nil }
            offset += n
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }

        let maxNew = min(900, input.count * 2 + 48)
        var bytes: [UInt8] = []
        var lastEmitted = ""
        var piece = [CChar](repeating: 0, count: 128)

        for _ in 0..<maxNew {
            var tok = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            let n = llama_token_to_piece(vocab, tok, &piece, Int32(piece.count), 0, false)
            if n > 0 {
                bytes.append(contentsOf: piece[0..<Int(n)].map { UInt8(bitPattern: $0) })
                if let s = String(bytes: bytes, encoding: .utf8), s != lastEmitted {
                    lastEmitted = s
                    onPartial(Self.clean(s))
                }
            }
            let rc = withUnsafeMutablePointer(to: &tok) { p -> Int32 in
                llama_decode(ctx, llama_batch_get_one(p, 1))
            }
            if rc != 0 { break }
        }

        let output = Self.clean(String(decoding: bytes, as: UTF8.self))
        // 结果明显不对（太短、太长）就放弃
        let inLen = Double(input.count), outLen = Double(output.count)
        guard outLen > 0, outLen >= inLen * 0.3, outLen <= inLen * 1.6 + 20 else { return nil }
        return output
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        let n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        guard n >= 0 else { return [] }
        return Array(tokens[0..<Int(n)])
    }

    private static func clean(_ s: String) -> String {
        var t = s
        if let r = t.range(of: "</think>") { t = String(t[r.upperBound...]) }
        t = t.replacingOccurrences(of: "<think>", with: "")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["整理后：", "整理后:", "整理后的文字：", "整理结果："] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if t.count >= 2, let f = t.first, let l = t.last,
           (f == "“" && l == "”") || (f == "\"" && l == "\"") || (f == "「" && l == "」") {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}
