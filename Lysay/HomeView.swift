import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HeaderView()
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
                    SetupStep(number: 4, title: "开始说话",
                              detail: "点键盘上的麦克风，第一次会跳到 Lysay，点左上角“◀ 返回”回到原应用即可开始听写")
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
                    if let err = coordinator.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("开始使用")
                }

                Section {
                    NavigationLink {
                        ClipboardView()
                    } label: {
                        HStack {
                            Label("粘贴板", systemImage: "doc.on.clipboard")
                            Spacer()
                            Text("\(coordinator.clips.count) 条")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("在这里保存常用内容，打字时点键盘上的粘贴板按钮，点一下即可输入。")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                }
            }
            .navigationTitle("Lysay")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var micStatusText: String {
        switch coordinator.micPermission {
        case .granted: return "已授权"
        case .denied: return "已拒绝，请在设置中开启"
        default: return "第一次使用时会询问"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(v) (\(b))"
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("LogoMark")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            Text("Lysay 语音输入")
                .font(.title2.bold())
            Text("边说边出字 · 注音输入 · 离线识别")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
