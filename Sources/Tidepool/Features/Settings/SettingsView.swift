import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置窗口：服务与账号 + 菜单栏 + 提醒 + 本地用量 + 通用 + 关于。
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var draggingID: UUID?

    var body: some View {
        Form {
            Section(T("服务与账号", "Services & accounts")) {
                ForEach(store.accounts) { account in
                    ProviderRowView(account: account, draggingID: $draggingID)
                        .onDrop(
                            of: [UTType.text],
                            delegate: ProviderDropDelegate(
                                target: account,
                                store: store,
                                draggingID: $draggingID
                            )
                        )
                }
                addProviderMenu
            }

            Section(T("菜单栏", "Menu bar")) {
                Picker(T("展示方式", "Display mode"), selection: styleBinding) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                if store.menuBarStyle == .single {
                    Picker(T("显示的 Provider", "Menu bar provider"), selection: selectedBinding) {
                        Text(T("自动（第一个）", "Automatic (first)")).tag(UUID?.none)
                        ForEach(store.visibleAccounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
                Toggle(T("使用彩色品牌图标", "Color brand icon"), isOn: colorBinding)
                Text(T(
                    "关闭时使用单色模板图标，自动适配浅色 / 深色菜单栏。",
                    "Off uses a monochrome template icon that adapts to light and dark menu bars."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Toggle(T("显示计价时段", "Show pricing window"), isOn: pricingBinding)
                Text(T(
                    "DeepSeek 工作日高峰为标准价，其余时段 5 折；金额下方橙色为标准价、青色为闲时。",
                    "DeepSeek charges standard rates during weekday peak hours and 50% off otherwise; an orange underline means peak, teal means off-peak."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(T("提醒", "Alerts")) {
                Toggle(T("低余额 / 低额度通知", "Low balance / quota alerts"), isOn: notificationBinding)
                Text(T(
                    "余额低于 ¥10 或任一额度低于 10% 时提醒；每个额度周期只提醒一次。",
                    "Alerts when the balance drops below ¥10 or any quota drops below 10%; once per cycle."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle(T("额度重置前提醒", "Quota reset reminders"), isOn: resetAlertBinding)
                Text(T(
                    "额度将在 1 小时内重置时提醒一次，避免浪费剩余额度。",
                    "Alerts once when a quota resets within an hour, so leftover quota doesn't go to waste."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(T("本地用量", "Local usage")) {
                Toggle(T("扫描本地会话统计 Tokens", "Scan local sessions for tokens"), isOn: usageBinding)
                HStack {
                    Button(T("打开用量明细…", "Open usage details…")) {
                        UsageWindowController.shared.show()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                Text(T(
                    "读取 OpenCode / Claude Code / Codex 的本地会话，只统计 token 与费用，不上传。",
                    "Reads local OpenCode / Claude Code / Codex sessions. Token and cost stats stay on this Mac."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(T("通用", "General")) {
                Picker(T("语言", "Language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                HStack {
                    Text(T("切换语言后需要重启 Tidepool 生效。", "Restart Tidepool to apply the language change."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(T("立即重启", "Restart now")) {
                        relaunch()
                    }
                    .controlSize(.small)
                }
                Toggle(T("隐私模式（隐藏金额）", "Privacy mode (hide amounts)"), isOn: privacyBinding)
                Toggle(T("登录时启动", "Launch at login"), isOn: launchBinding)
            }

            Section(T("关于", "About")) {
                LabeledContent(
                    T("版本", "Version"),
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2"
                )
                HStack {
                    Button(T("重新运行首次引导…", "Run onboarding again…")) {
                        Prefs.onboardingDone = false
                        OnboardingWindowController.shared.show(force: true)
                    }
                    .controlSize(.small)
                    Button(T("检查更新…", "Check for updates…")) {
                        UpdateChecker.openReleases()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                Text(T(
                    "所有数据仅保存在本机，API Key 存储在 macOS 钥匙串中；应用不包含任何遥测。",
                    "All data stays on this Mac. API keys live in the macOS Keychain. No telemetry."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 660, height: 660)
    }

    private var addProviderMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(ProviderID.allCases) { provider in
                    Button(T("添加 \(provider.displayName)", "Add \(provider.displayName)")) {
                        store.addAccount(provider: provider, name: provider.displayName)
                    }
                }
            } label: {
                Label(T("添加 Provider", "Add provider"), systemImage: "plus")
            }
            Text(T(
                "DeepSeek / Kimi 显示 API 余额；GLM / Kimi Code 显示套餐余量。",
                "DeepSeek / Kimi show API balance; GLM / Kimi Code show plan quotas."
            ))
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

    private var resetAlertBinding: Binding<Bool> {
        Binding(
            get: { store.resetAlertsEnabled },
            set: { store.setResetAlertsEnabled($0) }
        )
    }

    private var usageBinding: Binding<Bool> {
        Binding(
            get: { UsageStore.shared.enabled },
            set: { UsageStore.shared.setEnabled($0) }
        )
    }

    private var privacyBinding: Binding<Bool> {
        Binding(
            get: { store.privacyMode },
            set: { store.setPrivacyMode($0) }
        )
    }

    private var pricingBinding: Binding<Bool> {
        Binding(
            get: { store.showPricing },
            set: { store.setShowPricing($0) }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { Prefs.language },
            set: { Prefs.language = $0 }
        )
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// 拖拽排序：把 Provider 拖到另一行上时即时重排。
struct ProviderDropDelegate: DropDelegate {
    let target: ProviderAccount
    let store: AppStore
    @Binding var draggingID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggingID else { return false }
        return draggingID != target.id
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id else { return }
        store.moveAccount(id: draggingID, before: target.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

/// 单个 Provider 的编辑行：名称、密钥、站点、间隔、状态、排序与删除。
struct ProviderRowView: View {
    let account: ProviderAccount
    @Binding var draggingID: UUID?
    @Environment(AppStore.self) private var store
    @State private var keyInput: String
    @State private var hasStoredKey: Bool
    @State private var customExpanded = false

    init(account: ProviderAccount, draggingID: Binding<UUID?>) {
        self.account = account
        _draggingID = draggingID
        let stored = AppStore.shared.apiKey(for: account.id)?.isEmpty == false
        _hasStoredKey = State(initialValue: stored)
        _keyInput = State(initialValue: "")
        _customExpanded = State(initialValue: account.provider == .custom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .onDrag {
                        draggingID = account.id
                        return NSItemProvider(object: account.id.uuidString as NSString)
                    }
                    .help(T("拖动排序", "Drag to reorder"))

                ProviderGlyph(provider: account.provider, size: 14)
                TextField(T("名称", "Name"), text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .labelsHidden()
                    .frame(maxWidth: 180)
                Text(account.provider.kindDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(T("启用", "Enabled"), isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                rowMenu
            }

            HStack(spacing: 8) {
                SecureField("", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .labelsHidden()
                    .overlay(alignment: .leading) {
                        if keyInput.isEmpty {
                            Text(keyPlaceholder)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .allowsHitTesting(false)
                        }
                    }
                Button(hasStoredKey ? T("替换", "Replace") : T("保存并测试", "Save & test")) {
                    if !keyInput.isEmpty {
                        store.setAPIKey(id: account.id, key: keyInput)
                        hasStoredKey = true
                        keyInput = ""
                    }
                    Task { await store.refresh(account.id, force: true) }
                }
                .disabled(keyInput.isEmpty && !allowsEmptyKey)
                .controlSize(.small)
            }

            if supportsRegionPicker {
                HStack(spacing: 8) {
                    Picker(T("站点", "Region"), selection: regionBinding) {
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

            if account.provider == .custom {
                customConfigSection
            }

            HStack(spacing: 8) {
                Picker(T("刷新", "Refresh"), selection: intervalBinding) {
                    Text(T("1 分钟", "1 min")).tag(60)
                    Text(T("5 分钟", "5 min")).tag(300)
                    Text(T("10 分钟", "10 min")).tag(600)
                    Text(T("30 分钟", "30 min")).tag(1800)
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
        .opacity(draggingID == account.id ? 0.5 : 1)
    }

    // MARK: - 组件

    private var rowMenu: some View {
        Menu {
            Button(T("上移", "Move up")) { store.moveAccount(id: account.id, by: -1) }
            Button(T("下移", "Move down")) { store.moveAccount(id: account.id, by: 1) }
            Divider()
            Button(T("删除", "Delete"), role: .destructive) {
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
            Text(T("未验证", "Not verified"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 文案

    private var keyPlaceholder: String {
        if hasStoredKey {
            return T("已保存在钥匙串 · 输入新 Key 可替换", "Saved in Keychain · enter a new key to replace")
        }
        switch account.provider {
        case .glm: return T("粘贴 GLM Coding Plan API Key", "Paste GLM Coding Plan API key")
        case .kimiCode: return T("粘贴 Kimi For Coding API Key（sk-…）", "Paste Kimi For Coding API key (sk-…)")
        case .custom: return T("粘贴 API Key（无鉴权可留空）", "Paste API key (leave blank if no auth)")
        default: return T("粘贴 API Key", "Paste API key")
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
                RegionOption(
                    label: T("国内 · moonshot.cn", "China · moonshot.cn"),
                    url: URL(string: "https://api.moonshot.cn")!
                ),
                RegionOption(
                    label: T("国际 · moonshot.ai", "Global · moonshot.ai"),
                    url: URL(string: "https://api.moonshot.ai")!
                )
            ]
        case .glm:
            return [
                RegionOption(
                    label: T("智谱 · bigmodel.cn", "Zhipu · bigmodel.cn"),
                    url: URL(string: "https://open.bigmodel.cn")!
                ),
                RegionOption(
                    label: T("国际 · z.ai", "Global · z.ai"),
                    url: URL(string: "https://api.z.ai")!
                )
            ]
        default:
            return []
        }
    }

    private var regionHint: String {
        switch account.provider {
        case .moonshot:
            return T(
                "API Key 与站点必须匹配，混用会返回 401。",
                "The API key must match the region; mixing them returns 401."
            )
        case .glm:
            return T(
                "Coding Plan Key 与站点必须匹配；额度接口为只读。",
                "The Coding Plan key must match the region; quota APIs are read-only."
            )
        case .kimiCode:
            return T(
                "在 platform.kimi.com 的 Kimi For Coding 页面获取 Key。",
                "Get the key from Kimi For Coding on platform.kimi.com."
            )
        default:
            return T(
                "密钥只保存在 macOS 钥匙串，不会写入配置文件。",
                "Keys are stored only in the macOS Keychain, never in config files."
            )
        }
    }

    // MARK: - 自定义接口

    private var allowsEmptyKey: Bool {
        account.provider == .custom && (account.custom?.authStyle ?? .bearer) == .none
    }

    private var customConfig: CustomEndpointConfig {
        account.custom ?? CustomEndpointConfig()
    }

    private func customBinding<T>(_ keyPath: WritableKeyPath<CustomEndpointConfig, T>) -> Binding<T> {
        Binding(
            get: { customConfig[keyPath: keyPath] },
            set: { newValue in
                store.updateAccount(id: account.id) { account in
                    var config = account.custom ?? CustomEndpointConfig()
                    config[keyPath: keyPath] = newValue
                    account.custom = config
                }
            }
        )
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private var customConfigSection: some View {
        DisclosureGroup(isExpanded: $customExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                field(
                    T("Endpoint", "Endpoint"),
                    text: customBinding(\.endpoint),
                    placeholder: "https://api.example.com/v1/balance"
                )

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("鉴权方式", "Auth"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: customBinding(\.authStyle)) {
                            ForEach(CustomAuthStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("币种", "Currency"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("CNY", text: customBinding(\.currency))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 70)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("标签（可选）", "Label (optional)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField(T("自定义", "Custom"), text: customBinding(\.title))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .font(.system(size: 11))
                            .frame(width: 130)
                    }
                    Spacer()
                }

                field(
                    T("余额路径", "Balance path"),
                    text: customBinding(\.balancePath),
                    placeholder: "data.balance"
                )

                field(
                    T("百分比路径（0–100）", "Percent path (0–100)"),
                    text: customBinding(\.percentPath),
                    placeholder: "data.limits.0.remaining_percent"
                )
                Toggle(T("这个百分比是「已用」", "This percent is \"used\""), isOn: customBinding(\.percentIsUsed))
                    .controlSize(.small)

                field(
                    T("剩余量路径（可选）", "Remaining path (optional)"),
                    text: customBinding(\.remainingPath),
                    placeholder: "data.remaining"
                )
                field(
                    T("总量路径（可选）", "Total path (optional)"),
                    text: customBinding(\.totalPath),
                    placeholder: "data.total"
                )
                field(
                    T("重置时间路径（可选）", "Reset path (optional)"),
                    text: customBinding(\.resetPath),
                    placeholder: "data.reset_at"
                )

                Text(T(
                    "点路径用 . 访问 JSON，数组用数字下标。余额路径优先；没有余额时尝试百分比 / 剩余量+总量。",
                    "Use dots for JSON keys and numeric indexes for arrays. Balance wins; otherwise percent or remaining+total is used."
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Label(T("接口映射", "API mapping"), systemImage: "slider.horizontal.3")
                .font(.caption.weight(.medium))
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
