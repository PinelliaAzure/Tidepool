import AppKit
import Foundation
import Observation
import ServiceManagement

/// 全局状态中心：账户、快照、采样与菜单栏内容。
/// SwiftUI 通过 Observation 自动更新；菜单栏通过 onChange 回调手动刷新。
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var accounts: [ProviderAccount] = []
    private(set) var snapshots: [UUID: ProviderSnapshot] = [:]
    private(set) var states: [UUID: AccountState] = [:]
    private(set) var colorLogo: Bool
    private(set) var menuBarStyle: MenuBarStyle
    private(set) var notificationsEnabled: Bool
    private(set) var resetAlertsEnabled: Bool
    private(set) var privacyMode: Bool
    private(set) var showPricing: Bool

    /// 当前选中的 Provider（可观察，切换 Tab 时驱动 SwiftUI 重绘）。
    private(set) var selectedAccountID: UUID?

    var onMenuChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenUsage: (() -> Void)?

    /// 菜单栏余额告警阈值（元）。
    static let lowBalanceThreshold: Double = 10

    /// 调试预览（--preview）：用内存假数据渲染面板，不写任何持久化。
    private let isPreview: Bool

    private let keychain: KeychainStore
    private let sampleStore: SampleStore
    private let persistence: PersistenceController
    private let scheduler = RefreshScheduler()

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        let preview = arguments.contains("--preview")
            || arguments.contains("--preview-quota")
            || arguments.contains("--preview-usage")
            || arguments.contains("--preview-onboarding")
            || arguments.contains("--preview-settings")
            || arguments.contains("--demo-menu-bar")
        isPreview = preview
        colorLogo = Prefs.colorLogo
        menuBarStyle = Prefs.menuBarStyle
        notificationsEnabled = Prefs.notificationsEnabled
        resetAlertsEnabled = Prefs.resetAlertsEnabled
        privacyMode = Prefs.privacyMode
        showPricing = Prefs.showPricing
        keychain = KeychainStore()
        sampleStore = SampleStore(persistent: !preview)
        persistence = PersistenceController()
        selectedAccountID = preview ? nil : Prefs.selectedAccountID

        guard !preview else { return }

        accounts = persistence.loadAccounts().sorted { $0.sortOrder < $1.sortOrder }
        sampleStore.load()
        for account in accounts {
            states[account.id] = AccountState()
        }
    }

    /// 启动后台调度（App 启动完成后调用一次）。
    func bootstrap() {
        scheduler.attach(self)
        if notificationsEnabled || resetAlertsEnabled {
            NotificationManager.shared.requestAuthorization()
        }
    }

    // MARK: - 派生数据

    var visibleAccounts: [ProviderAccount] {
        accounts.filter(\.enabled)
    }

    var selectedAccount: ProviderAccount? {
        let visible = visibleAccounts
        if let id = selectedAccountID,
           let match = visible.first(where: { $0.id == id }) {
            return match
        }
        return visible.first
    }

    func samples(for id: UUID) -> [SamplePoint] {
        sampleStore.samples(for: id)
    }

    func quotaSamples(for id: UUID, kind: QuotaKind) -> [QuotaSamplePoint] {
        sampleStore.quotaSamples(for: id, kind: kind)
    }

    func apiKey(for id: UUID) -> String? {
        keychain.get(id)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - 菜单栏内容

    struct MenuBarContent {
        var text: String?
        var accent: NSColor?
        var provider: ProviderID?
        var alert: Bool
        /// 有计价时段时，金额下方状态线的颜色（橙=标准价，青=闲时）。
        var pricingTint: NSColor?
        var tooltip: String
    }

    var menuBarContent: MenuBarContent {
        let visible = visibleAccounts
        guard !visible.isEmpty else {
            return MenuBarContent(text: nil, accent: nil, alert: false, pricingTint: nil, tooltip: T("Tidepool — 点击添加 Provider", "Tidepool — click to add a provider"))
        }

        var text: String?
        var primary: ProviderAccount?

        switch menuBarStyle {
        case .single:
            primary = selectedAccount
            if let account = primary {
                text = compactValue(for: account)?.text
                    ?? (states[account.id]?.lastError != nil ? "…" : nil)
            }
        case .all:
            primary = selectedAccount
            let values = visible.compactMap { compactValue(for: $0)?.text }
            text = values.isEmpty ? nil : values.joined(separator: " · ")
        case .tightest:
            let quotaAccounts = visible.filter { !(snapshots[$0.id]?.quotas.isEmpty ?? true) }
            let candidates = quotaAccounts.isEmpty ? visible : quotaAccounts
            primary = candidates.min { lhs, rhs in
                (compactValue(for: lhs)?.health ?? 100.5) < (compactValue(for: rhs)?.health ?? 100.5)
            }
            if let account = primary {
                text = compactValue(for: account)?.text
                    ?? (states[account.id]?.lastError != nil ? "…" : nil)
            }
        }

        let alert = visible.contains(where: isAlert)
        let summary = visible.compactMap { account -> String? in
            guard let value = compactValue(for: account) else { return nil }
            return privacyMode ? account.name : "\(account.name) \(value.text)"
        }
        var tooltip = summary.isEmpty ? "Tidepool" : summary.joined(separator: " · ")

        var pricing: PricingStatus?
        if showPricing, let account = primary {
            pricing = ProviderPricing.status(for: account.provider)
        }

        if let account = primary {
            if let error = states[account.id]?.lastError {
                tooltip += " · ⚠︎ \(error)"
            } else if let ok = states[account.id]?.lastSuccess {
                tooltip += T(" · 更新于 \(TideFormatter.relative(ok) ?? "")", " · updated \(TideFormatter.relative(ok) ?? "")")
            }
        }
        if let pricing {
            tooltip += " · \(pricing.currentLabel)"
            tooltip += "（\(ProviderPricing.timeText(pricing.nextTransition, in: pricing.schedule)) \(pricing.nextLabel)）"
        }

        let pricingTint: NSColor?
        if showPricing, menuBarStyle != .all, let pricing {
            pricingTint = pricing.isOffPeak ? .systemTeal : .systemOrange
        } else {
            pricingTint = nil
        }

        return MenuBarContent(
            text: text,
            accent: primary?.provider.nsBrandColor,
            provider: menuBarStyle == .all ? nil : primary?.provider,
            alert: alert,
            pricingTint: pricingTint,
            tooltip: tooltip
        )
    }

    /// 单个账户在菜单栏里的紧凑值；额度型取最紧张的窗口。
    private func compactValue(for account: ProviderAccount) -> (text: String, health: Double?)? {
        guard let snapshot = snapshots[account.id] else { return nil }
        if let balance = snapshot.balance {
            if privacyMode {
                return (TideFormatter.currencySymbol(for: balance.currency) + "•••", nil)
            }
            return (TideFormatter.money(balance.total, currency: balance.currency, style: .menuBar), nil)
        }
        if let quota = snapshot.tightestQuota {
            return (privacyMode ? "•••" : TideFormatter.percent(quota.remainingPercent), quota.remainingPercent)
        }
        return nil
    }

    private func isAlert(_ account: ProviderAccount) -> Bool {
        guard let snapshot = snapshots[account.id] else { return false }
        if let balance = snapshot.balance {
            return !balance.isAvailable || balance.total <= Self.lowBalanceThreshold
        }
        return snapshot.quotas.contains { $0.remainingPercent <= 10 }
    }

    // MARK: - 账户管理

    @discardableResult
    func addAccount(provider: ProviderID, name: String) -> ProviderAccount {
        let account = ProviderAccount(
            provider: provider,
            name: name,
            sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1
        )
        accounts.append(account)
        states[account.id] = AccountState()
        persistAccounts()
        notify()
        return account
    }

    func updateAccount(id: UUID, mutate: (inout ProviderAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&accounts[index])
        persistAccounts()
        notify()
    }

    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        snapshots[id] = nil
        states[id] = nil
        keychain.delete(id)
        sampleStore.purge(accountID: id)
        if selectedAccountID == id {
            selectedAccountID = nil
        }
        if Prefs.selectedAccountID == id {
            Prefs.selectedAccountID = nil
        }
        persistAccounts()
        notify()
    }

    func setAPIKey(id: UUID, key: String) {
        do {
            try keychain.set(key, for: id)
        } catch {
            states[id]?.lastError = T("钥匙串写入失败", "Keychain write failed")
        }
        notify()
    }

    func setColorLogo(_ enabled: Bool) {
        colorLogo = enabled
        Prefs.colorLogo = enabled
        notify()
    }

    func setMenuBarStyle(_ style: MenuBarStyle) {
        menuBarStyle = style
        Prefs.menuBarStyle = style
        notify()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        Prefs.notificationsEnabled = enabled
        if enabled || resetAlertsEnabled {
            NotificationManager.shared.requestAuthorization()
        }
        notify()
    }

    func setResetAlertsEnabled(_ enabled: Bool) {
        resetAlertsEnabled = enabled
        Prefs.resetAlertsEnabled = enabled
        if enabled || notificationsEnabled {
            NotificationManager.shared.requestAuthorization()
        }
        notify()
    }

    func setPrivacyMode(_ enabled: Bool) {
        privacyMode = enabled
        Prefs.privacyMode = enabled
        notify()
    }

    func togglePrivacy() {
        setPrivacyMode(!privacyMode)
    }

    func setShowPricing(_ enabled: Bool) {
        showPricing = enabled
        Prefs.showPricing = enabled
        notify()
    }

    func requestUsage() {
        onOpenUsage?()
    }

    /// 调整 Provider 顺序（设置窗口的上下移动）。
    func moveAccount(id: UUID, by offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard accounts.indices.contains(target) else { return }
        accounts.swapAt(index, target)
        renumberAccounts()
        persistAccounts()
        notify()
    }

    /// 拖拽排序：把某个账户移动到另一个账户之前。
    func moveAccount(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let sourceIndex = accounts.firstIndex(where: { $0.id == id }),
              let targetIndex = accounts.firstIndex(where: { $0.id == targetID }) else { return }

        let account = accounts.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        accounts.insert(account, at: insertIndex)
        renumberAccounts()
        persistAccounts()
        notify()
    }

    private func renumberAccounts() {
        for index in accounts.indices {
            accounts[index].sortOrder = index
        }
    }

    func selectAccount(id: UUID?) {
        selectedAccountID = id
        if !isPreview {
            Prefs.selectedAccountID = id
        }
        notify()
    }

    func requestSettings() {
        onOpenSettings?()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // swift run 调试（非 .app 包）时无法注册登录项，忽略
        }
        notify()
    }

    // MARK: - 刷新

    @discardableResult
    func refresh(_ id: UUID, force: Bool = false) async -> Bool {
        guard let account = accounts.first(where: { $0.id == id }), account.enabled else { return false }
        guard force || states[id]?.isRefreshing != true else { return false }
        let storedKey = keychain.get(id) ?? ""
        guard account.allowsEmptyAPIKey || !storedKey.isEmpty else {
            states[id]?.lastError = T("未配置 API Key", "API key not configured")
            notify()
            return false
        }

        states[id]?.isRefreshing = true
        states[id]?.lastError = nil
        notify()
        defer {
            states[id]?.isRefreshing = false
            notify()
        }

        do {
            let provider: BalanceProviding
            if account.provider == .siliconFlow, SiliconFlowSession.decode(storedKey) != nil {
                provider = SiliconFlowConsoleProvider()
            } else if account.provider == .alibaba, CloudCredentials.decode(storedKey) != nil {
                provider = AlibabaCloudProvider()
            } else {
                provider = ProviderRegistry.make(for: account)
            }
            let snapshot = try await provider.fetch(apiKey: storedKey, baseURL: account.baseURL)
            snapshots[id] = snapshot
            states[id]?.lastSuccess = snapshot.fetchedAt
            if let total = snapshot.balance?.total {
                sampleStore.append(accountID: id, value: total, now: snapshot.fetchedAt)
            }
            for quota in snapshot.quotas {
                sampleStore.appendQuota(
                    accountID: id,
                    kind: quota.kind,
                    percent: quota.remainingPercent,
                    now: snapshot.fetchedAt
                )
            }
            if !isPreview {
                NotificationManager.shared.evaluate(
                    account: account,
                    snapshot: snapshot,
                    enabled: notificationsEnabled,
                    includeReset: resetAlertsEnabled
                )
            }
            notify()
            return true
        } catch {
            let message = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            states[id]?.lastError = message
            notify()
            return false
        }
    }

    func refreshAll(force: Bool = false) async {
        let ids = accounts.filter(\.enabled).map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.refresh(id, force: force)
                }
            }
        }
    }

    /// 退出应用前把合并中的采样立即落盘。
    func flushPendingWrites() {
        sampleStore.flush()
    }

    private func persistAccounts() {
        guard !isPreview else { return }
        persistence.saveAccounts(accounts)
    }

    private func notify() {
        onMenuChanged?()
    }

#if DEBUG
    /// 仅用于预览：不落 UserDefaults 的隐私模式开关。
    func setPreviewPrivacy(_ enabled: Bool) {
        privacyMode = enabled
        notify()
    }
#endif

#if DEBUG
    /// 仅用于 `--preview`：注入一份两账户的演示数据。
    func seedPreviewData() {
        guard isPreview, accounts.isEmpty else { return }

        let now = Date()
        let deepseek = ProviderAccount(provider: .deepseek, name: "DeepSeek", sortOrder: 0)
        let kimi = ProviderAccount(provider: .moonshot, name: "Kimi", sortOrder: 1)
        let glm = ProviderAccount(provider: .glm, name: "GLM", sortOrder: 2)
        let openrouter = ProviderAccount(provider: .openrouter, name: "OpenRouter", sortOrder: 3)
        let siliconflow = ProviderAccount(provider: .siliconFlow, name: "SiliconFlow", sortOrder: 4)
        let custom = ProviderAccount(
            provider: .custom,
            name: "My API",
            sortOrder: 5,
            custom: CustomEndpointConfig(
                endpoint: "https://example.com/v1/balance",
                authStyle: .bearer,
                currency: "CNY",
                balancePath: "data.balance",
                percentPath: "",
                percentIsUsed: false,
                remainingPath: "",
                totalPath: "",
                resetPath: "",
                title: "My API"
            )
        )
        accounts = [deepseek, kimi, glm, openrouter, siliconflow, custom]
        states[deepseek.id] = AccountState(isRefreshing: false, lastSuccess: now, lastError: nil)
        states[kimi.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-420), lastError: nil)
        states[glm.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-120), lastError: nil)
        states[openrouter.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-260), lastError: nil)
        states[siliconflow.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-300), lastError: nil)
        states[custom.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-180), lastError: nil)

        snapshots[deepseek.id] = ProviderSnapshot(
            fetchedAt: now,
            balance: BalanceSnapshot(
                currency: "CNY",
                total: 42.50,
                granted: 10,
                toppedUp: 32.5,
                isAvailable: true
            ),
            quotas: [],
            planName: nil
        )
        snapshots[kimi.id] = ProviderSnapshot(
            fetchedAt: now.addingTimeInterval(-420),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: 156.80,
                granted: 46.8,
                toppedUp: 110,
                isAvailable: true
            ),
            quotas: [],
            planName: nil
        )
        snapshots[glm.id] = ProviderSnapshot(
            fetchedAt: now.addingTimeInterval(-120),
            balance: nil,
            quotas: [
                QuotaWindow(
                    kind: .fiveHour,
                    remainingPercent: 72,
                    resetDate: now.addingTimeInterval(2 * 3600 + 18 * 60)
                ),
                QuotaWindow(
                    kind: .weekly,
                    remainingPercent: 88,
                    resetDate: now.addingTimeInterval(4 * 86_400 + 6 * 3600)
                ),
                QuotaWindow(
                    kind: .monthly,
                    remainingPercent: 64,
                    resetDate: now.addingTimeInterval(12 * 86_400)
                )
            ],
            planName: "GLM Coding Plan · Pro"
        )

        selectedAccountID = ProcessInfo.processInfo.arguments.contains("--preview-quota")
            ? glm.id
            : deepseek.id

        let deepseekValues: [Double] = [78, 74, 69, 63, 58, 50, 46, 42.5]
        for (index, value) in deepseekValues.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(deepseekValues.count - 1 - index), to: now)!
            sampleStore.append(accountID: deepseek.id, value: value, now: date)
        }
        let kimiValues: [Double] = [185, 180, 176, 170, 165, 160, 158, 156.8]
        for (index, value) in kimiValues.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(kimiValues.count - 1 - index), to: now)!
            sampleStore.append(accountID: kimi.id, value: value, now: date)
        }

        snapshots[openrouter.id] = ProviderSnapshot(
            fetchedAt: now.addingTimeInterval(-260),
            balance: BalanceSnapshot(currency: "USD", total: 57.5, granted: nil, toppedUp: 100, isAvailable: true),
            quotas: [],
            planName: "OpenRouter"
        )
        snapshots[siliconflow.id] = ProviderSnapshot(
            fetchedAt: now.addingTimeInterval(-300),
            balance: BalanceSnapshot(currency: "CNY", total: 12.34, granted: nil, toppedUp: 20, isAvailable: true),
            quotas: [],
            planName: "SiliconFlow"
        )
        snapshots[custom.id] = ProviderSnapshot(
            fetchedAt: now.addingTimeInterval(-180),
            balance: BalanceSnapshot(currency: "CNY", total: 88.8, granted: nil, toppedUp: 88.8, isAvailable: true),
            quotas: [],
            planName: "My API"
        )

        let glmWeekly: [Double] = [98, 95, 93, 91, 89, 88]
        for (index, percent) in glmWeekly.enumerated() {
            let date = Calendar.current.date(byAdding: .hour, value: -(glmWeekly.count - 1 - index) * 18, to: now)!
            sampleStore.appendQuota(accountID: glm.id, kind: .weekly, percent: percent, now: date)
        }
        sampleStore.appendQuota(accountID: glm.id, kind: .fiveHour, percent: 84, now: now.addingTimeInterval(-5 * 3600))
        sampleStore.appendQuota(accountID: glm.id, kind: .fiveHour, percent: 72, now: now.addingTimeInterval(-120))

        notify()
    }
#endif
}
