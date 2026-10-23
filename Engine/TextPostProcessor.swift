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

    static func process(_ raw: String, settings: AppSettings.Snapshot) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.removeFillers {
            text = removeFillers(text)
        }
        text = ChineseConverter.shared.convert(text, script: settings.script, variant: settings.variant)
        return text
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
