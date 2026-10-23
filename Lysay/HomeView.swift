import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var engine: SpeechEngine
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HeroCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    SetupStep(number: 1, title: "添加 Lysay 键盘",
                              detail: "设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › Lysay")
                    SetupStep(number: 2, title: "开启“允许完全访问”",
                              detail: "键盘需要它与 Lysay 通信，语音和文字只在本机处理，不会上传")
                    SetupStep(number: 3, title: "允许使用麦克风",
                              detail: micStatusText)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("打开 Lysay 设置", systemImage: "gear")
                    }
                    if coordinator.micPermission == .undetermined {
                        Button {
                            coordinator.ensureMic { _ in }
                        } label: {
                            Label("授权麦克风", systemImage: "mic")
                        }
                    }
                } header: {
                    Text("开始使用")
                } footer: {
                    Text("使用时点键盘上的麦克风，第一次会跳到 Lysay 开启录音，点左上角“◀ 返回”回到原应用就能开始说话。之后几分钟内不需要再跳转。")
                }

                Section("试一试") {
                    NavigationLink {
                        TryView()
                    } label: {
                        Label("语音输入测试", systemImage: "waveform.badge.mic")
                    }
                }

                Section {
                    Picker("输出文字", selection: $settings.script) {
                        Text("简体").tag(ScriptMode.hans)
                        Text("繁體").tag(ScriptMode.hant)
                    }
                    .pickerStyle(.segmented)
                    if settings.script == .hant {
                        Picker("繁體標準", selection: $settings.variant) {
                            ForEach(TraditionalVariant.allCases) { v in
                                Text(v.title).tag(v)
                            }
                        }
                    }
                } header: {
                    Text("简繁切换")
                } footer: {
                    Text("键盘左上角的“简/繁”按钮也可以随时切换。")
                }

                Section {
                    Toggle(isOn: $settings.refineEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Qwen3 精修")
                            Text("每句话说完后用 Qwen3-ASR 重新识别，自动加标点、纠错。约占 1GB 内存")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("去除语气词（嗯、呃、啊…）", isOn: $settings.removeFillers)
                    Toggle(isOn: $settings.liveCompose) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("实时上屏")
                            Text("说话时文字直接显示在输入框里（带下划线），精修后替换")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("后台保持麦克风", selection: $settings.keepAliveMinutes) {
                        Text("1 分钟").tag(1)
                        Text("3 分钟").tag(3)
                        Text("5 分钟").tag(5)
                        Text("10 分钟").tag(10)
                        Text("30 分钟").tag(30)
                    }
                } header: {
                    Text("识别")
                }

                Section {
                    StatusRow(title: "流式识别 · Paraformer", ok: engine.streamingReady,
                              text: engine.streamingReady ? "已就绪" : (engine.loadError ?? "加载中…"))
                    StatusRow(title: "精修 · Qwen3-ASR 0.6B", ok: engine.refineReady,
                              text: refineText)
                    StatusRow(title: "麦克风服务", ok: engine.micRunning,
                              text: engine.micRunning ? "运行中" : "未开启")
                    if engine.micRunning {
                        Button("立即关闭麦克风", role: .destructive) { coordinator.stopMic() }
                    }
                } header: {
                    Text("本地模型")
                } footer: {
                    Text("全部识别都在手机上离线完成。")
                }

                if let err = coordinator.lastError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("语音引擎", value: "sherpa-onnx 1.13.8")
                    LabeledContent("繁简词库", value: "OpenCC")
                }
            }
            .navigationTitle("Lysay")
        }
    }

    private var micStatusText: String {
        switch coordinator.micPermission {
        case .granted: return "已授权"
        case .denied: return "已拒绝，请在设置中开启"
        default: return "第一次使用时会询问"
        }
    }

    private var refineText: String {
        if !settings.refineEnabled { return "已关闭" }
        if engine.refineLoading { return "加载中…" }
        return engine.refineReady ? "已就绪" : "未加载"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(v) (\(b))"
    }
}

private struct HeroCard: View {
    @EnvironmentObject private var engine: SpeechEngine

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.lysay, Color.lysayPink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: 170, y: -60)

            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .lysayGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Lysay 语音输入")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("边说边出字 · 离线 Qwen3 精修 · 简繁切换")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.streamingReady ? Color.green : Color.yellow)
                        .frame(width: 8, height: 8)
                    Text(engine.streamingReady ? "模型已就绪" : "正在加载模型…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .lysayGlass(in: Capsule())
            }
            .padding(20)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.lysay))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool
    let text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
