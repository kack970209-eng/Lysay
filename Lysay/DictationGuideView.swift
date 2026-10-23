import SwiftUI

/// 从键盘跳转过来时显示：麦克风已开启，提示用户返回原应用继续说话。
struct DictationGuideView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var engine: SpeechEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.lysay.opacity(0.35), Color.lysayLight.opacity(0.25), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.backward")
                        .font(.headline)
                    Text("点左上角“◀ 返回”回到原应用")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .lysayGlass(in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                Spacer()

                MicOrb(size: 120, active: engine.micRunning, busy: !engine.streamingReady, level: engine.level)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if coordinator.micPermission == .denied {
                    Button("前往设置开启麦克风") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .lysayGlassButton(prominent: true)
                }

                Spacer()

                Button("留在 Lysay") { dismiss() }
                    .lysayGlassButton()
                    .padding(.bottom, 20)
            }
        }
    }

    private var title: String {
        if coordinator.micPermission == .denied { return "需要麦克风权限" }
        if !engine.streamingReady { return "正在加载语音模型…" }
        return engine.micRunning ? "Lysay 已准备好" : "正在开启麦克风…"
    }

    private var subtitle: String {
        if coordinator.micPermission == .denied {
            return "键盘本身不能录音，需要 Lysay 在后台帮你听写。"
        }
        return "返回刚才的应用后，键盘会自动开始听写。\n接下来 \(AppSettings.shared.keepAliveMinutes) 分钟内都不用再跳转。"
    }
}
