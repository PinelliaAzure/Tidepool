import SwiftUI
import ServiceManagement

/// 设置窗口：Providers 管理 + 菜单栏 + 提醒 + 通用 + 关于。
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
                Picker("展示方式", selection: styleBinding) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                if store.menuBarStyle == .single {
                    Picker("显示的 Provider", selection: selectedBinding) {
                        Text("自动（第一个）").tag(UUID?.none)
                        ForEach(store.visibleAccounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
                Toggle("使用彩色品牌图标", isOn: colorBinding)
                Text("关闭时使用单色模板图标，自动适配浅色 / 深色菜单栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("提醒") {
                Toggle("低余额 / 低额度通知", isOn: notificationBinding)
                Text("余额低于 ¥10 或任一额度低于 10% 时提醒；每个额度周期只提醒一次。")
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
        .frame(width: 620, height: 560)
    }

    private var addProviderMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(ProviderID.allCases) { provider in
                    Button("添加 \(provider.displayName)") {
                        store.addAccount(provider: provider, name: provider.displayName)
                    }
                }
            } label: {
                Label("添加 Provider", systemImage: "plus")
            }
            Text("DeepSeek / Kimi 显示 API 余额；GLM / Kimi Code 显示套餐余量。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedAccount?.id },
            set: { store.selectAccount(id: $0) }
        )
    }

    private var styleBinding: Binding<MenuBarStyle> {
        Binding(
            get: { store.menuBarStyle },
            set: { store.setMenuBarStyle($0) }
        )
    }

    private var colorBinding: Binding<Bool> {
        Binding(
            get: { store.colorLogo },
            set: { store.setColorLogo($0) }
        )
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { store.notificationsEnabled },
            set: { store.setNotificationsEnabled($0) }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }
}

/// 单个 Provider 的编辑行：名称、密钥、站点、间隔、状态、排序与删除。
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
                Text(account.provider.kindDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("启用", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                rowMenu
            }

            HStack(spacing: 8) {
                SecureField(keyPlaceholder, text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("保存并测试") {
                    store.setAPIKey(id: account.id, key: keyInput)
                    Task { await store.refresh(account.id, force: true) }
                }
                .disabled(keyInput.isEmpty)
                .controlSize(.small)
            }

            if supportsRegionPicker {
                HStack(spacing: 8) {
                    Picker("站点", selection: regionBinding) {
                        ForEach(regionOptions, id: \.self) { option in
                            Text(option.label).tag(option.url)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    Text(regionHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Text(regionHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 组件

    private var rowMenu: some View {
        Menu {
            Button("上移") { store.moveAccount(id: account.id, by: -1) }
            Button("下移") { store.moveAccount(id: account.id, by: 1) }
            Divider()
            Button("删除", role: .destructive) {
                store.removeAccount(id: account.id)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
                .lineLimit(1)
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

    // MARK: - 文案

    private var keyPlaceholder: String {
        switch account.provider {
        case .glm: return "粘贴 GLM Coding Plan API Key"
        case .kimiCode: return "粘贴 Kimi For Coding API Key（sk-…）"
        default: return "粘贴 API Key"
        }
    }

    private var supportsRegionPicker: Bool {
        account.provider == .moonshot || account.provider == .glm
    }

    private struct RegionOption: Hashable {
        let label: String
        let url: URL
    }

    private var regionOptions: [RegionOption] {
        switch account.provider {
        case .moonshot:
            return [
                RegionOption(label: "国内 · moonshot.cn", url: URL(string: "https://api.moonshot.cn")!),
                RegionOption(label: "国际 · moonshot.ai", url: URL(string: "https://api.moonshot.ai")!)
            ]
        case .glm:
            return [
                RegionOption(label: "智谱 · bigmodel.cn", url: URL(string: "https://open.bigmodel.cn")!),
                RegionOption(label: "国际 · z.ai", url: URL(string: "https://api.z.ai")!)
            ]
        default:
            return []
        }
    }

    private var regionHint: String {
        switch account.provider {
        case .moonshot: return "API Key 与站点必须匹配，混用会返回 401。"
        case .glm: return "Coding Plan Key 与站点必须匹配；额度接口为只读。"
        case .kimiCode: return "在 platform.kimi.com 的 Kimi For Coding 页面获取 Key。"
        default: return "密钥只保存在 macOS 钥匙串，不会写入配置文件。"
        }
    }

    // MARK: - 绑定

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

    private var regionBinding: Binding<URL> {
        Binding(
            get: { account.baseURL ?? account.provider.defaultBaseURL },
            set: { newValue in
                store.updateAccount(id: account.id) { $0.baseURL = newValue }
            }
        )
    }
}
