import Foundation

/// 简体 → 繁体转换，使用 OpenCC 词库，按“最长词优先”匹配。
/// 词库放在 App 包的 OpenCC/ 目录下。
final class ChineseConverter {
    static let shared = ChineseConverter()

    private struct Dict {
        var map: [String: String] = [:]
        var maxLen = 1
    }

    private let lock = NSLock()
    private var base: Dict?        // STPhrases + STCharacters
    private var taiwan: Dict?      // TWPhrases + TWVariantsPhrases + TWVariants
    private var hongkong: Dict?    // HKVariantsPhrases + HKVariants

    /// 提前加载词库，避免第一次转换时卡顿。
    func preload() {
        _ = dict(\.base, ["STPhrases", "STCharacters"])
    }

    func convert(_ text: String, script: ScriptMode, variant: TraditionalVariant) -> String {
        guard script == .hant, !text.isEmpty else { return text }
        var out = apply(dict(\.base, ["STPhrases", "STCharacters"]), to: text)
        switch variant {
        case .standard:
            break
        case .taiwan:
            out = apply(dict(\.taiwan, ["TWPhrases", "TWVariantsPhrases", "TWVariants"]), to: out)
        case .hongkong:
            out = apply(dict(\.hongkong, ["HKVariantsPhrases", "HKVariants"]), to: out)
        }
        return out
    }

    private func dict(_ keyPath: ReferenceWritableKeyPath<ChineseConverter, Dict?>, _ files: [String]) -> Dict {
        lock.lock(); defer { lock.unlock() }
        if let d = self[keyPath: keyPath] { return d }
        let d = load(files)
        self[keyPath: keyPath] = d
        return d
    }

    private func load(_ files: [String]) -> Dict {
        var d = Dict()
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "OpenCC"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                if line.hasPrefix("#") { continue }
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                if d.map[key] != nil { continue }
                guard let value = parts[1].split(separator: " ").first else { continue }
                d.map[key] = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
                d.maxLen = max(d.maxLen, key.count)
            }
        }
        d.maxLen = min(d.maxLen, 16)
        return d
    }

    private func apply(_ d: Dict, to text: String) -> String {
        let chars = Array(text)
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var i = 0
        while i < chars.count {
            var len = min(d.maxLen, chars.count - i)
            var matched = false
            while len > 0 {
                if let v = d.map[String(chars[i..<(i + len)])] {
                    out += v
                    i += len
                    matched = true
                    break
                }
                len -= 1
            }
            if !matched {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }
}
