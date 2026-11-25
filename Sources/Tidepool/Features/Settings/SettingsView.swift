import SwiftUI
import ServiceManagement

/// 设置窗口：Providers 管理 + 菜单栏 + 通用 + 关于。
struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(store.accounts) { account in
                    ProviderRowView(account: account)
                }
                addProviderMenu
            }

            Section("菜单栏") {
                Picker("显示的 Provider", selection: selectedBinding) {
                    Text("自动（第一个）").tag(UUID?.none)
                    ForEach(store.visibleAccounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                Toggle("使用彩色品牌图标", isOn: colorBinding)
                Text("关闭时使用单色模板图标，自动适配浅色 / 深色菜单栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通用") {
                Toggle("登录时启动", isOn: launchBinding)
            }

            Section("关于") {
                LabeledContent(
                    "版本",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
                )
                Text("所有数据仅保存在本机，API Key 存储在 macOS 钥匙串中；应用不包含任何遥测。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 540)
    }

    private var addProviderMenu: some View {
        Menu {
            ForEach(ProviderID.allCases) { provider in
                if provider.isConfigurable {
                    Button("添加 \(provider.displayName)") {
                        store.addAccount(provider: provider, name: provider.displayName)
                    }
                } else {
                    Button("\(provider.displayName)（即将支持）") {}
                        .disabled(true)
                }
            }
        } label: {
            Label("添加 Provider", systemImage: "plus")
        }
    }

    private var selectedBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedAccount?.id },
            set: { store.selectAccount(id: $0) }
        )
    }

    private var colorBinding: Binding<Bool> {
        Binding(
            get: { store.colorLogo },
            set: { store.setColorLogo($0) }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }
}

/// 单个 Provider 的编辑行：名称、密钥、间隔、状态、删除。
struct ProviderRowView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store
    @State private var keyInput: String

    init(account: ProviderAccount) {
        self.account = account
        _keyInput = State(initialValue: AppStore.shared.apiKey(for: account.id) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(account.provider.brandColor)
                    .frame(width: 8, height: 8)
                TextField("名称", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Spacer()
                Toggle("启用", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                SecureField("粘贴 API Key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("保存并测试") {
                    store.setAPIKey(id: account.id, key: keyInput)
                    Task { await store.refresh(account.id, force: true) }
                }
                .disabled(keyInput.isEmpty)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Picker("刷新", selection: intervalBinding) {
                    Text("1 分钟").tag(60)
                    Text("5 分钟").tag(300)
                    Text("10 分钟").tag(600)
                    Text("30 分钟").tag(1800)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()

                statusLabel

                Spacer()

                Button("删除", role: .destructive) {
                    store.removeAccount(id: account.id)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLabel: some View {
        let state = store.states[account.id]
        if state?.isRefreshing == true {
            ProgressView().controlSize(.mini)
        } else if let error = state?.lastError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
        } else if let updated = state?.lastSuccess {
            Text("✓ \(TideFormatter.relative(updated) ?? "")")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            Text("未验证")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { account.name },
            set: { newValue in
                store.updateAccount(id: account.id) { $0.name = newValue }
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { account.enabled },
            set: { newValue in
                store.updateAccount(id: account.id) { $0.enabled = newValue }
            }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { account.intervalSeconds },
            set: { newValue in
                store.updateAccount(id: account.id) { $0.intervalSeconds = newValue }
            }
        )
    }
}
