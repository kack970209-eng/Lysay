import SwiftUI

enum KeyboardMetrics {
    static let height: CGFloat = 272
    static let spacing: CGFloat = 6
    static let rowHeight: CGFloat = 44
}

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            TopBar(model: model)
                .frame(height: 38)
            Group {
                switch model.layout {
                case .voice:
                    VoicePanel(model: model)
                case .letters:
                    LetterPanel(model: model)
                case .numbers:
                    SymbolPanel(model: model, page: .numbers)
                case .symbols:
                    SymbolPanel(model: model, page: .symbols)
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .animation(.easeOut(duration: 0.15), value: model.hint)

            Button {
                model.switchLayout(model.layout == .voice ? .letters : .voice)
            } label: {
                Image(systemName: model.layout == .voice ? "keyboard" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 34)
                    .lysayGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)

            Button(action: model.dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 34)
                    .lysayGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private var placeholder: String {
        switch model.voiceState {
        case .listening: return "请说话…"
        case .processing: return "正在精修…"
        default: return "Lysay 语音输入"
        }
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
                        MicOrb(size: 92,
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

            BottomRow(model: model, leftLabel: "123", leftLayout: .numbers, showMic: false)
                .frame(height: KeyboardMetrics.rowHeight)
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

// MARK: - 字母面板

private struct LetterPanel: View {
    @ObservedObject var model: KeyboardModel
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }

    var body: some View {
        GeometryReader { geo in
            let keyWidth = (geo.size.width - KeyboardMetrics.spacing * 9) / 10
            VStack(spacing: 10) {
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
                BottomRow(model: model, leftLabel: "123", leftLayout: .numbers, showMic: true)
            }
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
                ["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"],
                ["。", "，", "、", "？", "！", "."],
            ]
        case .symbols:
            return [
                ["【", "】", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "—", "\\", "|", "～", "《", "》", "$", "&", "·"],
                ["…", "，", "^_^", "？", "！", "'"],
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let keyWidth = (geo.size.width - KeyboardMetrics.spacing * 9) / 10
            VStack(spacing: 10) {
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
                BottomRow(model: model, leftLabel: "ABC", leftLayout: .letters, showMic: true)
            }
        }
    }

    private func key(_ k: String) -> some View {
        KeyCap(text: k, style: .character) { model.insert(k) }
    }
}

// MARK: - 底栏

private struct BottomRow: View {
    @ObservedObject var model: KeyboardModel
    let leftLabel: String
    let leftLayout: KeyboardModel.Layout
    let showMic: Bool

    var body: some View {
        HStack(spacing: KeyboardMetrics.spacing) {
            KeyCap(text: leftLabel, style: .function) { model.switchLayout(leftLayout) }
                .frame(width: 52)
            if model.needsGlobe {
                KeyCap(systemImage: "globe", style: .function) { model.nextKeyboard() }
                    .frame(width: 44)
            }
            if showMic {
                KeyCap(systemImage: "mic.fill", style: .function) { model.switchLayout(.voice) }
                    .frame(width: 44)
            }
            KeyCap(text: "空格", style: .character) { model.space() }
            KeyCap(text: model.returnTitle, style: model.returnTitle == "换行" ? .function : .accent) {
                model.returnKey()
            }
            .frame(width: 88)
        }
        .frame(height: KeyboardMetrics.rowHeight)
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
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    init(text: String, style: KeyStyle, action: @escaping () -> Void) {
        self.text = text
        self.systemImage = nil
        self.style = style
        self.action = action
    }

    init(systemImage: String, style: KeyStyle, action: @escaping () -> Void) {
        self.text = nil
        self.systemImage = systemImage
        self.style = style
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
                        .font(.system(size: text.count > 1 ? 16 : 22))
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
