import SwiftUI

enum KeyboardMetrics {
    static let height: CGFloat = 292
    static let spacing: CGFloat = 6
    static let rowHeight: CGFloat = 42
    static let rowGap: CGFloat = 9
}

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if model.zhuyinComposing {
                    CandidateBar(model: model)
                } else {
                    TopBar(model: model)
                }
            }
            .frame(height: 38)

            Group {
                switch model.layout {
                case .voice:
                    VoicePanel(model: model)
                case .zhuyin:
                    ZhuyinPanel(model: model)
                case .letters:
                    LetterPanel(model: model)
                case .numbers:
                    SymbolPanel(model: model, page: .numbers)
                case .symbols:
                    SymbolPanel(model: model, page: .symbols)
                case .clipboard:
                    ClipboardPanel(model: model)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(height: KeyboardMetrics.height)
    }
}

// MARK: - 顶栏

private struct TopBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.toggleScript) {
                HStack(spacing: 2) {
                    Text("简").fontWeight(model.script == .hans ? .bold : .regular)
                        .foregroundStyle(model.script == .hans ? Color.primary : Color.secondary)
                    Text("/").foregroundStyle(.tertiary)
                    Text("繁").fontWeight(model.script == .hant ? .bold : .regular)
                        .foregroundStyle(model.script == .hant ? Color.primary : Color.secondary)
                }
                .font(.system(size: 15))
                .frame(width: 62, height: 34)
                .lysayGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                if let hint = model.hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else if !model.preview.isEmpty {
                    Text(model.preview)
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .animation(.easeOut(duration: 0.15), value: model.hint)

            BarIcon(systemImage: model.layout == .clipboard ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                    action: model.toggleClipboard)

            BarIcon(systemImage: model.layout == .voice ? "keyboard" : "mic") {
                model.switchLayout(model.layout == .voice ? model.textLayout : .voice)
            }

            BarIcon(systemImage: "keyboard.chevron.compact.down", action: model.dismissKeyboard)
        }
        .padding(.horizontal, 2)
    }

    private var placeholder: String {
        switch model.voiceState {
        case .listening: return "请说话…"
        case .processing: return "正在精修…"
        default: return model.layout == .zhuyin ? "注音輸入" : "Lysay"
        }
    }
}

private struct BarIcon: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 34)
                .lysayGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 注音候选字

private struct CandidateBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, c in
                        Button {
                            model.selectCandidate(c)
                        } label: {
                            Text(c.text)
                                .font(.system(size: 20, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Color.lysay : Color.primary)
                                .padding(.horizontal, 10)
                                .frame(minWidth: 40, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: model.candidates) { _, _ in
                proxy.scrollTo(0, anchor: .leading)
            }
        }
        .lysayGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 语音面板

private struct VoicePanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: KeyboardMetrics.spacing) {
            HStack(spacing: 0) {
                VStack(spacing: KeyboardMetrics.spacing) {
                    KeyCap(text: "，", style: .character) { model.insert("，") }
                    KeyCap(text: "。", style: .character) { model.insert("。") }
                    KeyCap(text: "？", style: .character) { model.insert("？") }
                }
                .frame(width: 66)

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Button(action: model.micTapped) {
                        MicOrb(size: 96,
                               active: model.voiceState == .listening,
                               busy: model.voiceState == .connecting || model.voiceState == .processing
                                   || model.voiceState == .loading,
                               level: model.level)
                    }
                    .buttonStyle(.plain)
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(spacing: KeyboardMetrics.spacing) {
                    KeyCap(text: "！", style: .character) { model.insert("！") }
                    KeyCap(text: "、", style: .character) { model.insert("、") }
                    RepeatKeyCap(systemImage: "delete.left", style: .function) { model.deleteBackward() }
                }
                .frame(width: 66)
            }
            .frame(maxHeight: .infinity)

            BottomRow(model: model, leftLabel: "123", leftLayout: .numbers,
                      switchLabel: "ㄅㄆㄇ", switchLayout: .zhuyin)
        }
    }

    private var status: String {
        switch model.voiceState {
        case .idle: return "点击说话"
        case .connecting: return "连接中…"
        case .listening: return "正在聆听，点击结束"
        case .processing: return "正在精修…"
        case .loading: return "模型加载中…"
        }
    }
}

// MARK: - 注音面板（大千排列，与 iOS 原生注音键盘一致）

private struct ZhuyinPanel: View {
    @ObservedObject var model: KeyboardModel

    private let rows: [[String]] = [
        ["ㄅ", "ㄉ", "ˇ", "ˋ", "ㄓ", "ˊ", "˙", "ㄚ", "ㄞ", "ㄢ", "ㄦ"],
        ["ㄆ", "ㄊ", "ㄍ", "ㄐ", "ㄔ", "ㄗ", "ㄧ", "ㄛ", "ㄟ", "ㄣ"],
        ["ㄇ", "ㄋ", "ㄎ", "ㄑ", "ㄕ", "ㄘ", "ㄨ", "ㄜ", "ㄠ", "ㄤ"],
        ["ㄈ", "ㄌ", "ㄏ", "ㄒ", "ㄖ", "ㄙ", "ㄩ", "ㄝ", "ㄡ", "ㄥ"],
    ]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let keyWidth = (geo.size.width - spacing * 10) / 11
            let keyHeight = (geo.size.height - KeyboardMetrics.rowGap * 4) / 5
            VStack(spacing: KeyboardMetrics.rowGap) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(rows[r], id: \.self) { k in
                            KeyCap(text: k, style: isTone(k) ? .function : .character, fontSize: 19) {
                                model.zhuyinKey(k)
                            }
                            .frame(width: keyWidth, height: keyHeight)
                        }
                        if r == 3 {
                            RepeatKeyCap(systemImage: "delete.left", style: .function) { model.deleteBackward() }
                                .frame(width: keyWidth, height: keyHeight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                BottomRow(model: model, leftLabel: "123", leftLayout: .numbers,
                          switchLabel: "ABC", switchLayout: .letters, punctuation: true)
                    .frame(height: keyHeight)
            }
        }
    }

    private func isTone(_ k: String) -> Bool {
        guard let c = k.first else { return false }
        return ZhuyinEngine.isTone(c)
    }
}

// MARK: - 字母面板

private struct LetterPanel: View {
    @ObservedObject var model: KeyboardModel
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }

    var body: some View {
        GeometryReader { geo in
            let keyWidth = (geo.size.width - KeyboardMetrics.spacing * 9) / 10
            let keyHeight = (geo.size.height - KeyboardMetrics.rowGap * 3) / 4
            VStack(spacing: KeyboardMetrics.rowGap) {
                HStack(spacing: KeyboardMetrics.spacing) {
                    ForEach(rows[0], id: \.self) { k in letter(k) }
                }
                HStack(spacing: KeyboardMetrics.spacing) {
                    ForEach(rows[1], id: \.self) { k in letter(k) }
                }
                .padding(.horizontal, keyWidth / 2)
                HStack(spacing: KeyboardMetrics.spacing) {
                    KeyCap(systemImage: shiftIcon, style: model.shifted ? .light : .function) {
                        model.shiftTapped()
                    }
                    .frame(width: keyWidth * 1.35)
                    Spacer(minLength: 2)
                    ForEach(rows[2], id: \.self) { k in letter(k).frame(width: keyWidth) }
                    Spacer(minLength: 2)
                    RepeatKeyCap(systemImage: "delete.left", style: .function) { model.deleteBackward() }
                        .frame(width: keyWidth * 1.35)
                }
                BottomRow(model: model, leftLabel: "123", leftLayout: .numbers,
                          switchLabel: "ㄅㄆㄇ", switchLayout: .zhuyin)
            }
            .frame(height: keyHeight * 4 + KeyboardMetrics.rowGap * 3)
        }
    }

    private var shiftIcon: String {
        model.capsLock ? "capslock.fill" : (model.shifted ? "shift.fill" : "shift")
    }

    private func letter(_ k: String) -> some View {
        KeyCap(text: (model.shifted || model.capsLock) ? k.uppercased() : k, style: .character) {
            model.insert(k)
        }
    }
}

// MARK: - 数字与符号

private struct SymbolPanel: View {
    enum Page { case numbers, symbols }

    @ObservedObject var model: KeyboardModel
    let page: Page

    private var rows: [[String]] {
        switch page {
        case .numbers:
            return [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", "：", "；", "（", "）", "$", "@", "「", "」"],
                ["。", "，", "、", "？", "！", "."],
            ]
        case .symbols:
            return [
                ["【", "】", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "—", "\\", "|", "～", "《", "》", "『", "』", "·"],
                ["…", "；", "^_^", "？", "！", "'"],
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let keyWidth = (geo.size.width - KeyboardMetrics.spacing * 9) / 10
            let keyHeight = (geo.size.height - KeyboardMetrics.rowGap * 3) / 4
            VStack(spacing: KeyboardMetrics.rowGap) {
                HStack(spacing: KeyboardMetrics.spacing) {
                    ForEach(rows[0], id: \.self) { k in key(k) }
                }
                HStack(spacing: KeyboardMetrics.spacing) {
                    ForEach(rows[1], id: \.self) { k in key(k) }
                }
                HStack(spacing: KeyboardMetrics.spacing) {
                    KeyCap(text: page == .numbers ? "#+=" : "123", style: .function) {
                        model.switchLayout(page == .numbers ? .symbols : .numbers)
                    }
                    .frame(width: keyWidth * 1.35)
                    Spacer(minLength: 2)
                    ForEach(rows[2], id: \.self) { k in key(k).frame(width: keyWidth * 1.15) }
                    Spacer(minLength: 2)
                    RepeatKeyCap(systemImage: "delete.left", style: .function) { model.deleteBackward() }
                        .frame(width: keyWidth * 1.35)
                }
                BottomRow(model: model,
                          leftLabel: model.textLayout == .zhuyin ? "ㄅㄆㄇ" : "ABC",
                          leftLayout: model.textLayout,
                          switchLabel: nil, switchLayout: nil)
            }
            .frame(height: keyHeight * 4 + KeyboardMetrics.rowGap * 3)
        }
    }

    private func key(_ k: String) -> some View {
        KeyCap(text: k, style: .character) { model.insert(k) }
    }
}

// MARK: - 粘贴板

private struct ClipboardPanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: KeyboardMetrics.spacing) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    Button(action: model.pasteSystemClipboard) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(Color.lysay)
                            Text("粘贴系统剪贴板的内容")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .lysayGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)

                    if model.clips.isEmpty {
                        Text("还没有保存的内容\n在 Lysay App 里点“粘贴板”添加常用文字")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    } else {
                        ForEach(model.clips) { item in
                            ClipRow(item: item) { model.insertClip(item) }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
            }

            HStack(spacing: KeyboardMetrics.spacing) {
                KeyCap(text: "返回", style: .function) { model.closeClipboard() }
                    .frame(width: 64)
                KeyCap(text: "空格", style: .character) { model.space() }
                RepeatKeyCap(systemImage: "delete.left", style: .function) { model.deleteBackward() }
                    .frame(width: 56)
                KeyCap(text: model.returnTitle, style: model.returnTitle == "换行" ? .function : .accent) {
                    model.returnKey()
                }
                .frame(width: 80)
            }
            .frame(height: KeyboardMetrics.rowHeight)
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(item.text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(KeyPalette.fill(.character, scheme: scheme, pressed: false))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 底栏

private struct BottomRow: View {
    @ObservedObject var model: KeyboardModel
    let leftLabel: String
    let leftLayout: KeyboardModel.Layout
    let switchLabel: String?
    let switchLayout: KeyboardModel.Layout?
    var punctuation = false

    var body: some View {
        HStack(spacing: KeyboardMetrics.spacing) {
            KeyCap(text: leftLabel, style: .function, fontSize: 15) { model.switchLayout(leftLayout) }
                .frame(width: 50)
            if model.needsGlobe {
                KeyCap(systemImage: "globe", style: .function) { model.nextKeyboard() }
                    .frame(width: 42)
            }
            if let switchLabel, let switchLayout {
                KeyCap(text: switchLabel, style: .function, fontSize: 15) { model.switchLayout(switchLayout) }
                    .frame(width: 54)
            }
            if punctuation {
                KeyCap(text: "，", style: .character) { model.insert("，") }
                    .frame(width: 36)
            }
            KeyCap(text: "空格", style: .character, fontSize: 15) { model.space() }
            if punctuation {
                KeyCap(text: "。", style: .character) { model.insert("。") }
                    .frame(width: 36)
            }
            KeyCap(text: returnTitle, style: returnStyle, fontSize: 15) {
                model.returnKey()
            }
            .frame(width: 76)
        }
        .frame(maxHeight: KeyboardMetrics.rowHeight)
    }

    private var returnTitle: String {
        model.zhuyinComposing ? "確認" : model.returnTitle
    }

    private var returnStyle: KeyStyle {
        model.zhuyinComposing || model.returnTitle != "换行" ? .accent : .function
    }
}

// MARK: - 按键

enum KeyStyle {
    case character, function, light, accent
}

struct KeyCap: View {
    var text: String?
    var systemImage: String?
    var style: KeyStyle
    var fontSize: CGFloat?
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    init(text: String, style: KeyStyle, fontSize: CGFloat? = nil, action: @escaping () -> Void) {
        self.text = text
        self.systemImage = nil
        self.style = style
        self.fontSize = fontSize
        self.action = action
    }

    init(systemImage: String, style: KeyStyle, action: @escaping () -> Void) {
        self.text = nil
        self.systemImage = systemImage
        self.style = style
        self.fontSize = nil
        self.action = action
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(KeyPalette.fill(style, scheme: scheme, pressed: pressed))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.22), radius: 0, x: 0, y: 1)
            Group {
                if let text {
                    Text(text)
                        .font(.system(size: fontSize ?? (text.count > 1 ? 16 : 22)))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .regular))
                }
            }
            .foregroundStyle(style == .accent ? Color.white : Color.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: KeyboardMetrics.rowHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in
                    pressed = false
                    action()
                }
        )
    }
}

/// 长按连续触发（删除键）
struct RepeatKeyCap: View {
    var systemImage: String
    var style: KeyStyle
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(KeyPalette.fill(style, scheme: scheme, pressed: pressed))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.22), radius: 0, x: 0, y: 1)
            Image(systemName: pressed ? systemImage + ".fill" : systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: KeyboardMetrics.rowHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                    }
                }
                .onEnded { _ in
                    pressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

enum KeyPalette {
    static func fill(_ style: KeyStyle, scheme: ColorScheme, pressed: Bool) -> Color {
        let dark = scheme == .dark
        switch style {
        case .character, .light:
            if pressed { return dark ? Color(white: 0.5) : Color(white: 0.82) }
            return dark ? Color(white: 0.42, opacity: 0.9) : Color.white
        case .function:
            if pressed { return dark ? Color(white: 0.42) : Color.white }
            return dark ? Color(white: 0.27, opacity: 0.9) : Color(white: 0.70, opacity: 0.85)
        case .accent:
            return pressed ? Color.lysay.opacity(0.7) : Color.lysay
        }
    }
}
