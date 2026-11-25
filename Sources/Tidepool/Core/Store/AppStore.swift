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

    var onMenuChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    /// 菜单栏余额告警阈值（元）。
    static let lowBalanceThreshold: Double = 10

    /// 调试预览（--preview）：用内存假数据渲染面板，不写任何持久化。
    private let isPreview: Bool

    private let keychain: KeychainStore
    private let sampleStore: SampleStore
    private let persistence: PersistenceController
    private let scheduler = RefreshScheduler()

    private init() {
        let preview = ProcessInfo.processInfo.arguments.contains("--preview")
        isPreview = preview
        colorLogo = Prefs.colorLogo
        keychain = KeychainStore()
        sampleStore = SampleStore(persistent: !preview)
        persistence = PersistenceController()

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
    }

    // MARK: - 派生数据

    var visibleAccounts: [ProviderAccount] {
        accounts.filter(\.enabled)
    }

    var selectedAccount: ProviderAccount? {
        let visible = visibleAccounts
        if let id = Prefs.selectedAccountID,
           let match = visible.first(where: { $0.id == id }) {
            return match
        }
        return visible.first
    }

    func samples(for id: UUID) -> [SamplePoint] {
        sampleStore.samples(for: id)
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
        var alert: Bool
        var tooltip: String
    }

    var menuBarContent: MenuBarContent {
        guard let account = selectedAccount else {
            return MenuBarContent(text: nil, accent: nil, alert: false, tooltip: "Tidepool — 点击添加 Provider")
        }
        let snapshot = snapshots[account.id]
        let state = states[account.id]
        var tooltip = account.name
        var alert = false
        var text: String?

        if let balance = snapshot?.balance {
            text = TideFormatter.money(balance.total, currency: balance.currency, style: .menuBar)
            tooltip += " · 余额 \(TideFormatter.money(balance.total, currency: balance.currency, style: .hero))"
            if !balance.isAvailable || balance.total <= Self.lowBalanceThreshold {
                alert = true
            }
        } else if !(snapshot?.quotas.isEmpty ?? true) {
            // 额度型 Provider（GLM / Kimi Code，M1 接入）
            if let tightest = snapshot?.quotas.min(by: { $0.remainingPercent < $1.remainingPercent }) {
                text = TideFormatter.percent(tightest.remainingPercent)
                if tightest.remainingPercent <= 10 { alert = true }
            }
        } else if state?.lastError != nil {
            text = "…"
        }

        if let error = state?.lastError {
            tooltip += " · ⚠︎ \(error)"
        } else if let ok = state?.lastSuccess {
            tooltip += " · 更新于 \(TideFormatter.relative(ok) ?? "")"
        }

        return MenuBarContent(
            text: text,
            accent: account.provider.nsBrandColor,
            alert: alert,
            tooltip: tooltip
        )
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
            states[id]?.lastError = "钥匙串写入失败"
        }
        notify()
    }

    func setColorLogo(_ enabled: Bool) {
        colorLogo = enabled
        Prefs.colorLogo = enabled
        notify()
    }

    func selectAccount(id: UUID?) {
        Prefs.selectedAccountID = id
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
        guard let key = keychain.get(id), !key.isEmpty else {
            states[id]?.lastError = "未配置 API Key"
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
            let provider = ProviderRegistry.make(for: account.provider)
            let snapshot = try await provider.fetch(apiKey: key, baseURL: account.baseURL)
            snapshots[id] = snapshot
            states[id]?.lastSuccess = snapshot.fetchedAt
            if let total = snapshot.balance?.total {
                sampleStore.append(accountID: id, value: total, now: snapshot.fetchedAt)
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
        for account in accounts where account.enabled {
            await refresh(account.id, force: force)
        }
    }

    private func persistAccounts() {
        guard !isPreview else { return }
        persistence.saveAccounts(accounts)
    }

    private func notify() {
        onMenuChanged?()
    }

#if DEBUG
    /// 仅用于 `--preview`：注入一份两账户的演示数据。
    func seedPreviewData() {
        guard isPreview, accounts.isEmpty else { return }

        let now = Date()
        let deepseek = ProviderAccount(provider: .deepseek, name: "DeepSeek", sortOrder: 0)
        let kimi = ProviderAccount(provider: .moonshot, name: "Kimi", sortOrder: 1)
        accounts = [deepseek, kimi]
        states[deepseek.id] = AccountState(isRefreshing: false, lastSuccess: now, lastError: nil)
        states[kimi.id] = AccountState(isRefreshing: false, lastSuccess: now.addingTimeInterval(-420), lastError: nil)

        snapshots[deepseek.id] = ProviderSnapshot(
            fetchedAt: now,
            balance: BalanceSnapshot(
                currency: "CNY",
                total: 42.50,
                granted: 10,
                toppedUp: 32.5,
                isAvailable: true
            ),
            quotas: []
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
            quotas: []
        )

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

        notify()
    }
#endif
}
