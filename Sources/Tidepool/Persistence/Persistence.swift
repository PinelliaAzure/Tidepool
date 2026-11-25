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
}
