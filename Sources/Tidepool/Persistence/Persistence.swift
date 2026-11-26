import Foundation

// MARK: - 偏好（UserDefaults）

enum Prefs {
    private static let defaults = UserDefaults.standard

    /// 菜单栏当前展示的账户。
    static var selectedAccountID: UUID? {
        get { defaults.string(forKey: "menu.selectedAccountID").flatMap(UUID.init) }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: "menu.selectedAccountID")
            } else {
                defaults.removeObject(forKey: "menu.selectedAccountID")
            }
        }
    }

    /// 菜单栏使用彩色品牌图标（关闭则为单色模板图标）。
    static var colorLogo: Bool {
        get { defaults.bool(forKey: "menu.colorLogo") }
        set { defaults.set(newValue, forKey: "menu.colorLogo") }
    }

    /// 菜单栏展示策略：当前 / 全部 / 最紧张。
    static var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: "menu.style") ?? "") ?? .single }
        set { defaults.set(newValue.rawValue, forKey: "menu.style") }
    }

    /// 低余额 / 低额度通知，默认开启。
    static var notificationsEnabled: Bool {
        get {
            if defaults.object(forKey: "alerts.enabled") == nil { return true }
            return defaults.bool(forKey: "alerts.enabled")
        }
        set { defaults.set(newValue, forKey: "alerts.enabled") }
    }

    /// 扫描本地会话统计用量，默认开启。
    static var usageScanEnabled: Bool {
        get {
            if defaults.object(forKey: "usage.enabled") == nil { return true }
            return defaults.bool(forKey: "usage.enabled")
        }
        set { defaults.set(newValue, forKey: "usage.enabled") }
    }

    /// 隐私模式：隐藏金额 / 项目等敏感信息。
    static var privacyMode: Bool {
        get { defaults.bool(forKey: "privacy.enabled") }
        set { defaults.set(newValue, forKey: "privacy.enabled") }
    }

    /// 首次启动引导是否完成。
    static var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboarding.done") }
        set { defaults.set(newValue, forKey: "onboarding.done") }
    }

    /// 菜单栏是否显示计价时段（月亮角标 / tooltip）。
    static var showPricing: Bool {
        get {
            if defaults.object(forKey: "pricing.showInMenuBar") == nil { return true }
            return defaults.bool(forKey: "pricing.showInMenuBar")
        }
        set { defaults.set(newValue, forKey: "pricing.showInMenuBar") }
    }

    /// 额度重置前提醒，默认开启。
    static var resetAlertsEnabled: Bool {
        get {
            if defaults.object(forKey: "alerts.reset") == nil { return true }
            return defaults.bool(forKey: "alerts.reset")
        }
        set { defaults.set(newValue, forKey: "alerts.reset") }
    }

    /// 界面语言，重启生效。
    static var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "ui.language") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "ui.language") }
    }
}

// MARK: - 本地持久化（Application Support/Tidepool）

struct PersistenceController {
    private let directory: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        directory = support.appendingPathComponent("Tidepool", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var accountsURL: URL { directory.appendingPathComponent("accounts.json") }
    private var samplesURL: URL { directory.appendingPathComponent("samples.json") }
    private var quotaSamplesURL: URL { directory.appendingPathComponent("quota-samples.json") }

    func loadAccounts() -> [ProviderAccount] {
        guard let raw = try? Data(contentsOf: accountsURL) else { return [] }
        return (try? JSONDecoder().decode([ProviderAccount].self, from: raw)) ?? []
    }

    func saveAccounts(_ accounts: [ProviderAccount]) {
        if let data = try? JSONEncoder().encode(accounts) {
            try? data.write(to: accountsURL, options: .atomic)
        }
    }

    func loadSamples() -> [UUID: [SamplePoint]] {
        guard let raw = try? Data(contentsOf: samplesURL),
              let decoded = try? JSONDecoder().decode([String: [SamplePoint]].self, from: raw)
        else { return [:] }
        var result: [UUID: [SamplePoint]] = [:]
        for (key, value) in decoded {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = value
        }
        return result
    }

    func saveSamples(_ samples: [UUID: [SamplePoint]]) {
        let mapped = Dictionary(uniqueKeysWithValues: samples.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(mapped) {
            try? data.write(to: samplesURL, options: .atomic)
        }
    }

    func loadQuotaSamples() -> [UUID: [QuotaSamplePoint]] {
        guard let raw = try? Data(contentsOf: quotaSamplesURL),
              let decoded = try? JSONDecoder().decode([String: [QuotaSamplePoint]].self, from: raw)
        else { return [:] }
        var result: [UUID: [QuotaSamplePoint]] = [:]
        for (key, value) in decoded {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = value
        }
        return result
    }

    func saveQuotaSamples(_ samples: [UUID: [QuotaSamplePoint]]) {
        let mapped = Dictionary(uniqueKeysWithValues: samples.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(mapped) {
            try? data.write(to: quotaSamplesURL, options: .atomic)
        }
    }
}
