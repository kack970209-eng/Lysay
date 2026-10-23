import Foundation

/// 正在拼的一个注音音节：声母 + 介音 + 韵母 + 声调。
/// 和大千键盘一样，同一类符号后按的会替换先按的。
struct ZhuyinSyllable {
    static let initials: Set<Character> = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    static let medials: Set<Character> = Set("ㄧㄨㄩ")
    static let finals: Set<Character> = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    static let tones: Set<Character> = Set("ˊˇˋ˙")

    var initial: Character?
    var medial: Character?
    var final: Character?
    private var order: [Character] = []

    var isEmpty: Bool { initial == nil && medial == nil && final == nil }

    var text: String {
        var s = ""
        if let initial { s.append(initial) }
        if let medial { s.append(medial) }
        if let final { s.append(final) }
        return s
    }

    mutating func insert(_ c: Character) {
        if Self.initials.contains(c) {
            if let old = initial { order.removeAll { $0 == old } }
            initial = c
        } else if Self.medials.contains(c) {
            if let old = medial { order.removeAll { $0 == old } }
            medial = c
        } else if Self.finals.contains(c) {
            if let old = final { order.removeAll { $0 == old } }
            final = c
        } else {
            return
        }
        order.append(c)
    }

    mutating func removeLast() {
        guard let c = order.popLast() else { return }
        if initial == c { initial = nil } else if medial == c { medial = nil } else if final == c { final = nil }
    }

    /// 完成音节，一声不标符号
    func completed(tone: Character?) -> String {
        guard let tone, tone != "ˉ" else { return text }
        return text + String(tone)
    }
}

/// 注音输入：音节缓冲、整句转换（动态规划选最高分路径）、候选字。
final class ZhuyinEngine {
    struct Candidate: Hashable {
        let text: String
        let consumes: Int   // 用掉前面几个音节
    }

    private let dict = ZhuyinDictionary.shared
    private(set) var syllables: [String] = []
    private(set) var current = ZhuyinSyllable()

    var isComposing: Bool { !syllables.isEmpty || !current.isEmpty }

    static func isZhuyinKey(_ c: Character) -> Bool {
        ZhuyinSyllable.initials.contains(c) || ZhuyinSyllable.medials.contains(c)
            || ZhuyinSyllable.finals.contains(c)
    }

    static func isTone(_ c: Character) -> Bool { ZhuyinSyllable.tones.contains(c) }

    func inputSymbol(_ c: Character) {
        current.insert(c)
    }

    /// 输入声调；没有正在拼的音节时返回 false
    @discardableResult
    func inputTone(_ c: Character?) -> Bool {
        guard !current.isEmpty else { return false }
        syllables.append(current.completed(tone: c))
        current = ZhuyinSyllable()
        return true
    }

    func backspace() {
        if !current.isEmpty {
            current.removeLast()
        } else if !syllables.isEmpty {
            syllables.removeLast()
        }
    }

    func reset() {
        syllables = []
        current = ZhuyinSyllable()
    }

    /// 输入框里显示的组字：已转换的字 + 正在拼的注音
    var displayText: String {
        convert(syllables) + current.text
    }

    func candidates(limit: Int = 120) -> [Candidate] {
        guard !syllables.isEmpty else { return [] }
        var result: [Candidate] = []
        var seen = Set<String>()
        if syllables.count > 1 {
            let whole = convert(syllables)
            result.append(Candidate(text: whole, consumes: syllables.count))
            seen.insert(whole)
        }
        var k = min(6, syllables.count)
        while k >= 1 {
            let key = syllables[0..<k].joined(separator: "-")
            if let entry = dict.lookup(key) {
                for v in entry.values where !seen.contains(v) {
                    seen.insert(v)
                    result.append(Candidate(text: v, consumes: k))
                    if result.count >= limit { return result }
                }
            }
            k -= 1
        }
        if result.isEmpty {
            // 词库里没有这个读音，直接给注音本身
            result.append(Candidate(text: syllables[0], consumes: 1))
        }
        return result
    }

    /// 选了候选字：去掉它用掉的音节，返回要上屏的文字
    func select(_ c: Candidate) -> String {
        syllables.removeFirst(min(c.consumes, syllables.count))
        return c.text
    }

    /// 全部确认上屏
    func commitAll() -> String {
        let text = displayText
        reset()
        return text
    }

    private func convert(_ sy: [String]) -> String {
        let n = sy.count
        guard n > 0 else { return "" }
        var best = [Double](repeating: -.infinity, count: n + 1)
        var back = [(from: Int, text: String)](repeating: (0, ""), count: n + 1)
        best[0] = 0
        for j in 1...n {
            for i in max(0, j - 6)..<j where best[i] > -.infinity {
                let key = sy[i..<j].joined(separator: "-")
                if let e = dict.lookup(key), let top = e.values.first {
                    let score = best[i] + e.score
                    if score > best[j] {
                        best[j] = score
                        back[j] = (i, top)
                    }
                }
            }
            if best[j] == -.infinity {
                // 无效读音：原样保留注音，并给很低的分数
                best[j] = best[j - 1] - 20
                back[j] = (j - 1, sy[j - 1])
            }
        }
        var parts: [String] = []
        var j = n
        while j > 0 {
            parts.append(back[j].text)
            j = back[j].from
        }
        return parts.reversed().joined()
    }
}
