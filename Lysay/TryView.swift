import SwiftUI

/// App 内的语音输入测试页，不用键盘也能体验识别效果。
struct TryView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var engine: SpeechEngine

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        if coordinator.testCommitted.isEmpty && coordinator.testLive.isEmpty {
                            Text("点下方按钮开始说话，文字会随你说话实时出现；每句话停顿后，Qwen3 会精修成带标点的句子。")
                                .foregroundStyle(.secondary)
                        } else {
                            (Text(coordinator.testCommitted)
                             + Text(coordinator.testLive).foregroundColor(.secondary))
                                .font(.title3)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onChange(of: coordinator.testLive) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            VStack(spacing: 6) {
                Button {
                    coordinator.toggleTestDictation()
                } label: {
                    MicOrb(size: 88,
                           active: engine.state == .listening,
                           busy: engine.state == .processing || engine.state == .loading,
                           level: engine.level)
                }
                .buttonStyle(.plain)
                .disabled(!engine.streamingReady)

                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("语音输入测试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = coordinator.testCommitted
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(coordinator.testCommitted.isEmpty)
                Button {
                    coordinator.clearTest()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private var statusText: String {
        if !engine.streamingReady { return "正在加载模型…" }
        switch engine.state {
        case .listening: return "正在聆听，再点一下结束"
        case .processing: return "正在精修…"
        case .loading: return "正在加载模型…"
        case .ready: return "点击开始说话"
        }
    }
}
