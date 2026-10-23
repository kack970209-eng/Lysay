import AuthenticationServices
import SwiftUI

/// 首页的账号区块
struct AccountSection: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section {
            if let p = account.profile, account.isLoggedIn {
                NavigationLink {
                    AccountDetailView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.lysay)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.user.name?.isEmpty == false ? p.user.name! : (p.user.email ?? "Lysay 用户"))
                                .font(.body.weight(.medium))
                            Text(planSummary(p))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !p.ai.pro {
                    Button {
                        coordinator.showAccount = true
                    } label: {
                        Label("升级 Pro，AI 语音无限使用", systemImage: "sparkles")
                    }
                }
            } else {
                SignInButtons()
            }
            if let err = account.errorMessage {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("账号")
        } footer: {
            if !account.isLoggedIn {
                Text("登录后可免费使用 4 小时 AI 语音，并在多台设备同步粘贴板。注音打字与粘贴板不需要登录。")
            }
        }
    }

    private func planSummary(_ p: AccountManager.Profile) -> String {
        if let plan = p.plan, p.ai.pro {
            let date = Date(timeIntervalSince1970: plan.expiresAt / 1000).formatted(date: .abbreviated, time: .omitted)
            return "\(plan.name) · \(date) 到期"
        }
        let remain = account.remainingFreeSeconds ?? 0
        return "免费版 · AI 语音剩余 \(formatDuration(remain))"
    }
}

struct SignInButtons: View {
    @EnvironmentObject private var account: AccountManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                account.handleApple(result)
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                account.signInWithGoogle()
            } label: {
                HStack(spacing: 8) {
                    Text("G").font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    Text("使用 Google 登录").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)

            if account.busy {
                ProgressView("登录中…")
            }
        }
        .padding(.vertical, 6)
    }
}

/// 账号详情：额度、套餐、同步、退出、删除
struct AccountDetailView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let p = account.profile {
                Section("账号") {
                    LabeledContent("名字", value: p.user.name ?? "-")
                    LabeledContent("Email", value: p.user.email ?? "-")
                    LabeledContent("登录方式", value: p.user.provider == "apple" ? "Apple" : "Google")
                    LabeledContent("用户 ID") {
                        Text(p.user.id).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Section("AI 语音") {
                    if p.ai.pro, let plan = p.plan {
                        LabeledContent("方案", value: plan.name)
                        LabeledContent("到期",
                                       value: Date(timeIntervalSince1970: plan.expiresAt / 1000)
                                        .formatted(date: .long, time: .omitted))
                    } else {
                        LabeledContent("方案", value: "免费版")
                        LabeledContent("剩余免费时长", value: formatDuration(account.remainingFreeSeconds ?? 0))
                        Button("升级 Pro") { coordinator.showAccount = true }
                    }
                }
                Section {
                    LabeledContent("上次同步",
                                   value: account.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "尚未同步")
                    Button("立即同步") { account.syncNow() }
                } header: {
                    Text("粘贴板同步")
                } footer: {
                    Text("剪贴板记录与收藏文件夹会同步到你的账号。")
                }
                Section {
                    Button("退出登录") {
                        account.signOut()
                        dismiss()
                    }
                    Button("删除账号", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("我的账号")
        .refreshable { account.refresh() }
        .confirmationDialog("删除账号会清除云端的所有资料，且无法复原。", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("删除账号", role: .destructive) {
                account.deleteAccount()
                dismiss()
            }
        }
    }
}

/// 升级 Pro（目前由管理员在后台开通）
struct ProUpgradeView: View {
    @EnvironmentObject private var account: AccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image("LogoMark")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("Lysay Pro").font(.title2.bold())
                        Text("AI 语音输入无限使用：边说边出字，按 ✓ 后 AI 整理成通顺的一段话。所有模型都在手机本地运行。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                if let p = account.profile, !p.ai.pro {
                    Section {
                        LabeledContent("免费 AI 语音剩余", value: formatDuration(account.remainingFreeSeconds ?? 0))
                    }
                }

                Section("方案") {
                    if account.plans.isEmpty {
                        ProgressView()
                    }
                    ForEach(account.plans) { plan in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plan.name).font(.headline)
                                Text("\(plan.days) 天").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(currencySymbol(plan.currency))\(plan.price)")
                                .font(.title3.bold())
                                .foregroundStyle(Color.lysay)
                        }
                    }
                }

                if let p = account.profile {
                    Section {
                        Button {
                            UIPasteboard.general.string = p.user.id
                            copied = true
                        } label: {
                            LabeledContent(copied ? "已复制用户 ID" : "复制我的用户 ID") {
                                Text(String(p.user.id.prefix(8)) + "…").font(.caption.monospaced())
                            }
                        }
                    } header: {
                        Text("开通方式")
                    } footer: {
                        Text("请把用户 ID 提供给 Lysay 客服完成付款开通。开通后回到 App 下拉刷新即可生效。")
                    }
                } else {
                    Section {
                        SignInButtons()
                    } footer: {
                        Text("请先登录，再开通 Pro。")
                    }
                }
            }
            .navigationTitle("升级 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .refreshable { account.refresh() }
            .onAppear {
                account.loadPlans()
                account.refresh()
            }
        }
    }

    private func currencySymbol(_ c: String) -> String {
        switch c.uppercased() {
        case "TWD": return "NT$"
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        case "HKD": return "HK$"
        default: return c + " "
        }
    }
}

/// 专有名词：让 AI 语音保持英文名、品牌名原样
struct HotwordsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var newWord = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("新增词语，例如 Lysay", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("新增", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("说话里常出现的英文名、品牌名、人名加在这里，识别和 AI 整理时会照原样保留，不会一下中文一下英文。")
            }
            Section {
                ForEach(settings.hotwords, id: \.self) { w in
                    Text(w)
                }
                .onDelete { settings.hotwords.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("专有名词")
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: " ")
        guard !w.isEmpty, !settings.hotwords.contains(w) else { return }
        settings.hotwords.append(w)
        newWord = ""
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return "\(h) 小时 \(m) 分" }
    return "\(m) 分钟"
}
