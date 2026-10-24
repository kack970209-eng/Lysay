import SwiftUI

/// App Store 截图用的示范画面：以 `-LysayDemo <画面>` 启动 App 时显示。
/// voice / polish / zhuyin / clipboard：模拟聊天 App 下方显示 Lysay 键盘；home、pro：App 本身的页面。
struct DemoView: View {
    let mode: String
    @StateObject private var model = KeyboardModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mode {
        case "home":
            HomeView()
        case "pro":
            ProUpgradeView()
        default:
            VStack(spacing: 0) {
                ChatMock(mode: mode)
                KeyboardRootView(model: model)
                    .padding(.bottom, 34)
                    .background(
                        (scheme == .dark ? Color(white: 0.17) : Color(red: 0.82, green: 0.84, blue: 0.87))
                            .ignoresSafeArea()
                    )
            }
            .onAppear { model.applyDemo(mode) }
        }
    }
}

private struct ChatMock: View {
    let mode: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 52, height: 52)
                    .overlay(Text("美").font(.title3.bold()).foregroundStyle(.white))
                Text("小美").font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.bar)

            ScrollView {
                VStack(spacing: 8) {
                    Bubble(text: "明天的會議幾點開始？", mine: false)
                    Bubble(text: "我確認一下行事曆", mine: true)
                    Bubble(text: "好，順便問一下新版本什麼時候上線", mine: false)
                    if mode == "clipboard" {
                        Bubble(text: "地址傳給我一下", mine: false)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                HStack {
                    if mode == "zhuyin" {
                        Text("今天天氣很好")
                            .underline()
                            .foregroundStyle(.primary)
                    } else {
                        Text("iMessage").foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct Bubble: View {
    let text: String
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 60) }
            Text(text)
                .font(.body)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(mine ? Color.blue : Color(.secondarySystemBackground))
                )
            if !mine { Spacer(minLength: 60) }
        }
    }
}
