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

    /// 「全部」模式的分项。
    struct MenuBarItem {
        var provider: ProviderID
        /// 紧凑值（已带颜色：低余额黄 / 归零红 / 默认）。
        var value: NSAttributedString
        /// 右下角圆点：峰时红 / 谷时绿 / 其他白，全平台统一。
        var dotColor: NSColor
    }

    struct MenuBarContent {
        /// 单 / 紧凑模式的菜单栏文字（已带颜色）。
        var title: NSAttributedString?
        var provider: ProviderID?
        var tooltip: String
        /// 单 Provider 模式下主账户 logo 右下角的圆点颜色。
        var dotColor: NSColor?
        /// 「全部」模式的分项：每个 Provider 一个品牌 logo + 紧凑值（隐私模式下已打码）。
        var allItems: [MenuBarItem] = []
    }

    var menuBarContent: MenuBarContent {
        let visible = visibleAccounts
        guard !visible.isEmpty else {
            return MenuBarContent(
                title: nil,
                provider: nil,
                tooltip: T("Tidepool — 点击添加 Provider", "Tidepool — click to add a provider")
            )
        }

        var title: NSAttributedString?
        var primary: ProviderAccount?
        var allItems: [MenuBarItem] = []
        var dotColor: NSColor?

        switch menuBarStyle {
        case .single:
            primary = selectedAccount
            if let account = primary {
                if let value = compactValue(for: account) {
                    title = menuBarText(value, color: valueColor(for: account))
                } else if states[account.id]?.lastError != nil {
                    title = menuBarText("…", color: nil)
                }
                dotColor = statusDotColor(for: account.provider)
            }
        case .all:
            primary = selectedAccount
            for account in visible {
                guard let value = compactValue(for: account) else { continue }
                let text = menuBarText(value, color: valueColor(for: account))
                allItems.append(
                    MenuBarItem(
                        provider: account.provider,
                        value: text,
                        dotColor: statusDotColor(for: account.provider)
                    )
                )
            }
            title = joinedMenuBarText(allItems.map(\.value))
        case .allCompact:
            primary = selectedAccount
            let values = visible.map { account -> NSAttributedString? in
                guard let value = compactValue(for: account) else { return nil }
                return menuBarText(value, color: valueColor(for: account))
            }.compactMap { $0 }
            title = joinedMenuBarText(values)
        }

        let summary = visible.compactMap { account -> String? in
            guard let value = compactValue(for: account) else { return nil }
            return privacyMode ? account.name : "\(account.name) \(value)"
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

        return MenuBarContent(
            title: title,
            provider: menuBarStyle == .single ? primary?.provider : nil,
            tooltip: tooltip,
            dotColor: menuBarStyle == .single ? dotColor : nil,
            allItems: allItems
        )
    }

    /// 菜单栏数值的默认字体与颜色（低余额黄 / 归零红 / 默认跟随系统）。
    private func menuBarText(_ string: String, color: NSColor?) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: color ?? NSColor.labelColor
            ]
        )
    }

    private let menuBarSeparator = NSAttributedString(
        string: " · ",
        attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    )

    private func joinedMenuBarText(_ parts: [NSAttributedString]) -> NSAttributedString? {
        guard !parts.isEmpty else { return nil }
        let joined = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { joined.append(menuBarSeparator) }
            joined.append(part)
        }
        return joined
    }

    /// 右下角圆点颜色——全平台统一：峰时红·常亮，谷时绿·常亮，
    /// 没有峰谷定价的渠道白点。目前只有 DeepSeek 有官方峰谷定价。
    /// 圆点是状态指示，不受「菜单栏显示计价时段」开关影响。
    private func statusDotColor(for provider: ProviderID) -> NSColor {
        guard let pricing = ProviderPricing.status(for: provider) else {
            return NSColor.white
        }
        return pricing.isOffPeak ? .systemGreen : .systemRed
    }

    /// 数值文字颜色：归零（含负数）红；余额 ≤¥10 或最紧张额度 ≤10% 黄；正常默认色。
    private func valueColor(for account: ProviderAccount) -> NSColor? {
        guard let snapshot = snapshots[account.id] else { return nil }
        if let balance = snapshot.balance {
            if balance.total <= 0 { return .systemRed }
            if balance.total <= Self.lowBalanceThreshold { return .systemYellow }
            return nil
        }
        // 额度型（火山方舟 / GLM / Kimi Code 等）：最紧张窗口剩余 ≤10% 黄，归零红
        if let quota = snapshot.tightestQuota {
            if quota.remainingPercent <= 0 { return .systemRed }
            if quota.remainingPercent <= 10 { return .systemYellow }
        }
        return nil
    }

    /// 单个账户在菜单栏里的紧凑值；额度型取最紧张的窗口。
    private func compactValue(for account: ProviderAccount) -> String? {
        guard let snapshot = snapshots[account.id] else { return nil }
        if let balance = snapshot.balance {
            return privacyMode
                ? TideFormatter.currencySymbol(for: balance.currency) + "•••"
                : TideFormatter.money(balance.total, currency: balance.currency, style: .menuBar)
        }
        if let quota = snapshot.tightestQuota {
            return privacyMode ? "•••" : TideFormatter.percent(quota.remainingPercent)
        }
        return nil
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
