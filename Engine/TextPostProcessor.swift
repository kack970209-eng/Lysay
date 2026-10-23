import Foundation

/// 识别结果的后处理：去语气词、整理标点、简繁转换。
enum TextPostProcessor {
    private static let punct = "，。！？、；：,.!?;:"

    // 前面是句首或标点，后面是标点或句尾的语气词，例如 “嗯，” “啊，” “呃”
    private static let standaloneFiller = try! NSRegularExpression(
        pattern: "(^|[，。！？、；,.!?;\\s])(?:嗯+|呃+|额+|唔+|啊+|哎+|诶+|欸+)(?=[，。！？、；,.!?;\\s]|$)[，、,]?",
        options: [])
    // 嗯/呃 基本不会出现在正常词语里，句中直接删掉
    private static let hardFiller = try! NSRegularExpression(pattern: "[嗯呃]+[，、,]?", options: [])
    // 句首的 “那个，” “就是说，”
    private static let leadingFiller = try! NSRegularExpression(
        pattern: "(^|[。！？!?]\\s*)(?:那个|这个|就是说|然后呢)[，、,]", options: [])
    private static let repeatedPunct = try! NSRegularExpression(pattern: "([，、,])[，、,]+", options: [])
    private static let commaBeforeStop = try! NSRegularExpression(pattern: "[，、,]+([。！？!?])", options: [])

    // “我我我” → “我”（同一个字连续 3 次以上）
    private static let charStutter = try! NSRegularExpression(pattern: "([\\u4e00-\\u9fff])\\1{2,}", options: [])
    // “我，我，我想” → “我想”
    private static let commaStutter = try! NSRegularExpression(
        pattern: "([\\u4e00-\\u9fff]{1,2})(?:[，、,]\\s*\\1)+(?=[，、,]?)", options: [])
    // “然后然后” “就是就是” → 只留一个
    private static let wordStutter = try! NSRegularExpression(pattern: "([\\u4e00-\\u9fff]{2,4})\\1+", options: [])

    /// 去掉结巴和重复的字词
    static func collapseStutter(_ input: String) -> String {
        var text = replace(commaStutter, in: input, with: "$1")
        text = replace(charStutter, in: text, with: "$1")
        text = replace(wordStutter, in: text, with: "$1")
        return text
    }

    /// AI 整理失败时的退路：规则清理
    static func ruleBasedPolish(_ raw: String) -> String {
        var text = collapseStutter(raw)
        text = removeFillers(text)
        return ensureEnding(text, isLast: true)
    }

    /// 只做简繁转换，并统一专有名词的写法
    static func convertScript(_ text: String, settings: AppSettings.Snapshot) -> String {
        let converted = ChineseConverter.shared.convert(text, script: settings.script, variant: settings.variant)
        return normalizeHotwords(converted, hotwords: settings.hotwords)
    }

    /// 英文专有名词不论识别成 LYSAY、lysay、Ly say，都统一成设定的写法
    static func normalizeHotwords(_ text: String, hotwords: [String]) -> String {
        var out = text
        for word in hotwords {
            let letters = word.filter { !$0.isWhitespace }
            guard letters.count >= 2, letters.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { continue }
            let pattern = "(?i)(?<![A-Za-z0-9])" + letters.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "[\\s\\-]?") + "(?![A-Za-z0-9])"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = re.stringByReplacingMatches(in: out, range: range,
                                              withTemplate: NSRegularExpression.escapedTemplate(for: word))
        }
        return out
    }

    static func process(_ raw: String, settings: AppSettings.Snapshot) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.removeFillers {
            text = removeFillers(text)
        }
        return convertScript(text, settings: settings)
    }

    /// 流式识别没有标点，给没有精修的句子补一个结尾标点。
    static func ensureEnding(_ text: String, isLast: Bool) -> String {
        guard let last = text.last else { return text }
        if punct.contains(last) { return text }
        return text + (isLast ? "。" : "，")
    }

    static func removeFillers(_ input: String) -> String {
        var text = input
        // 连续的语气词（“嗯，啊，”）第一次只能删掉一个，所以跑两遍
        text = replace(standaloneFiller, in: text, with: "$1")
        text = replace(standaloneFiller, in: text, with: "$1")
        text = replace(hardFiller, in: text, with: "")
        text = replace(leadingFiller, in: text, with: "$1")
        text = replace(repeatedPunct, in: text, with: "$1")
        text = replace(commaBeforeStop, in: text, with: "$1")
        while let first = text.first, "，、,".contains(first) {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
