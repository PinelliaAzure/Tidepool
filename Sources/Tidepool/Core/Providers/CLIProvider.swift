import Foundation

// MARK: - 官方 CLI 调用

enum CLIProviderError: LocalizedError {
    case missing(tool: String, hint: String)
    case failed(tool: String, message: String)

    var errorDescription: String? {
        switch self {
        case .missing(let tool, let hint):
            return T(
                "未检测到 \(tool)。\(hint)",
                "\(tool) not found. \(hint)"
            )
        case .failed(let tool, let message):
            return T(
                "\(tool) 读取失败：\(message)",
                "\(tool) failed: \(message)"
            )
        }
    }
}

enum CLIExecutor {
    static func find(_ tool: String) -> String? {
        for directory in searchDirectories {
            let path = directory + "/" + tool
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func json(tool: String, arguments: [String], installHint: String) throws -> Any {
        guard let binary = find(tool) else {
            throw CLIProviderError.missing(tool: tool, hint: installHint)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (searchDirectories + [environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            throw CLIProviderError.failed(tool: tool, message: error.localizedDescription)
        }

        if group.wait(timeout: .now() + 30) == .timedOut {
            process.terminate()
            throw CLIProviderError.failed(tool: tool, message: T("读取超时", "timed out"))
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: output, encoding: .utf8) ?? ""
        let errorText = String(data: errorOutput, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            // 有些 CLI（例如未登录的 arkcli）把结构化错误写到 stderr 并以非 0 退出；
            // 交给 Provider 解析，才能给出「未登录 / 无订阅 / 权限不足」这类可操作提示。
            if let object = firstJSON(in: Data(errorText.utf8)) ?? firstJSON(in: output) {
                return object
            }
            throw CLIProviderError.failed(tool: tool, message: shortMessage(errorText.isEmpty ? text : errorText))
        }
        guard let object = firstJSON(in: output) else {
            throw CLIProviderError.failed(tool: tool, message: shortMessage(text.isEmpty ? "no output" : text))
        }
        return object
    }

    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = [
            home + "/.local/bin",
            home + "/.npm-global/bin",
            home + "/.volta/bin",
            home + "/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for version in versions.sorted().reversed() where version.hasPrefix("v") {
                directories.append(nvm + "/" + version + "/bin")
            }
        }

        let python = home + "/Library/Python"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: python) {
            for version in versions {
                directories.append(python + "/" + version + "/bin")
            }
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        return Array(NSOrderedSet(array: directories).compactMap { $0 as? String })
    }

    private static func firstJSON(in data: Data) -> Any? {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let slice = text[start...end]
        return try? JSONSerialization.jsonObject(with: Data(slice.utf8))
    }

    private static func shortMessage(_ text: String) -> String {
        let line = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "unknown error"
        return String(line.prefix(160))
    }
}

// MARK: - 火山方舟 Coding Plan

struct VolcengineCLIProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let json = try CLIExecutor.json(
            tool: "arkcli",
            // 不写死 product：默认会自动发现 Agent Plan / Coding Plan。
            arguments: ["usage", "plan", "--format", "json"],
            installHint: T(
                "先运行 npm install -g @volcengine/ark-cli，再执行 arkcli auth login volc-sso。",
                "Run npm install -g @volcengine/ark-cli, then arkcli auth login volc-sso."
            )
        )
        return try Self.parse(json)
    }

    static func parse(_ json: Any) throws -> ProviderSnapshot {
        guard let root = json as? [String: Any] else {
            throw ProviderError.network(T("响应不是 JSON 对象", "Response is not a JSON object"))
        }
        if root["ok"] as? Bool == false,
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            let lower = message.lowercased()
            if lower.contains("not configured") || lower.contains("auth login") || lower.contains("logged_in") {
                throw ProviderError.notSupported(
                    T(
                        "火山方舟尚未登录 arkcli。请在设置里点「浏览器登录」，完成火山 SSO 后再点「检测」。",
                        "arkcli is not signed in. In Settings, use “Browser sign-in”, finish Volcengine SSO, then click Check."
                    )
                )
            }
            throw ProviderError.notSupported(message)
        }
        guard let items = root["items"] as? [[String: Any]] else {
            throw ProviderError.notSupported(T("没有读到额度数据", "No quota data"))
        }

        // 默认 auto-discover 会返回 Agent Plan / Coding Plan（个人版 / 团队版）。
        // 优先个人版；团队版没有绑定 seat 时 periods 为空，会被过滤掉。
        let candidates = items.filter { item in
            (item["subscribed"] as? Bool) != false
                && !((item["periods"] as? [[String: Any]]) ?? []).isEmpty
        }
        let item = candidates.first { ($0["edition"] as? String) == "personal" }
            ?? candidates.first
        guard let item else {
            if let message = items.compactMap({ $0["error"] as? String }).first(where: { !$0.isEmpty }) {
                throw ProviderError.notSupported(message)
            }
            throw ProviderError.notSupported(
                T("没有找到 Agent Plan / Coding Plan 订阅", "No Agent Plan or Coding Plan subscription found")
            )
        }
        if let error = item["error"] as? String, !error.isEmpty {
            throw ProviderError.notSupported(error)
        }

        var quotas: [QuotaWindow] = []
        for period in item["periods"] as? [[String: Any]] ?? [] {
            let kind: QuotaKind?
            switch (period["label"] as? String)?.lowercased() {
            case "session", "5h", "five_hour": kind = .fiveHour
            case "weekly", "week": kind = .weekly
            case "monthly", "month": kind = .monthly
            default: kind = nil
            }
            guard let kind else { continue }

            // Coding Plan 通常直接给 percent；Agent Plan 可能给 used/total，percent 为 0。
            let percent: Double?
            if let value = period["percent"] as? NSNumber {
                percent = value.doubleValue
            } else if let used = (period["used"] as? NSNumber)?.doubleValue,
                      let total = (period["total"] as? NSNumber)?.doubleValue,
                      total > 0 {
                percent = used / total * 100
            } else {
                percent = nil
            }
            guard let percent else { continue }

            quotas.append(
                QuotaWindow(
                    kind: kind,
                    remainingPercent: min(max(100 - percent, 0), 100),
                    resetDate: ISO8601Date.parse(period["reset_at"] as? String)
                )
            )
        }
        guard !quotas.isEmpty else {
            throw ProviderError.notSupported(T("没有可读取的额度窗口", "No quota windows found"))
        }

        let product = item["product"] as? String ?? ""
        let family: String
        switch product {
        case "agent-plan": family = "Ark Agent Plan"
        case "coding-plan": family = "Ark Coding Plan"
        case "agent-plan-team": family = "Ark Agent Plan Team"
        case "coding-plan-team": family = "Ark Coding Plan Team"
        default: family = "Ark Plan"
        }
        let tier = item["tier"] as? String
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: quotas.sorted { $0.kind.sortOrder < $1.kind.sortOrder },
            planName: tier.map { "\(family) · \($0.capitalized)" } ?? family
        )
    }
}

// MARK: - 阿里云百炼 Coding Plan

struct AlibabaCLIProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let installHint = T(
            "先运行 curl -fsSL https://bailian.aliyun.com/cli/install.sh | BAILIAN_SKIP_SKILL_INIT=1 bash，再执行 bl auth login --console。",
            "Install the Bailian CLI from https://bailian.aliyun.com/cli, then run bl auth login --console."
        )

        // 百炼有 Coding Plan 和 Token Plan 两套配额，账号通常只有其中一种。
        do {
            let json = try CLIExecutor.json(
                tool: "bl",
                arguments: ["usage", "coding-plan", "--output", "json"],
                installHint: installHint
            )
            return try Self.parse(json)
        } catch {
            // 只有明确的「没有 Coding Plan」才继续尝试 Token Plan；
            // 未安装 / 未登录 / 网络错误直接抛出，避免误导成没有套餐。
            guard Self.shouldTryTokenPlan(after: error) else { throw error }
        }

        do {
            let json = try CLIExecutor.json(
                tool: "bl",
                arguments: ["usage", "token-plan", "--output", "json"],
                installHint: installHint
            )
            return try Self.parseTokenPlan(json)
        } catch let error as CLIProviderError {
            throw error
        } catch {
            throw ProviderError.notSupported(
                T(
                    "已登录，但没有找到 Coding Plan / Token Plan 配额。可在设置里填 AccessKey 读账户余额。",
                    "Signed in, but no Coding Plan or Token Plan quota was found. Enter an AccessKey in Settings to read the account balance."
                )
            )
        }
    }

    static func shouldTryTokenPlan(after error: Error) -> Bool {
        let message: String
        switch error {
        case let CLIProviderError.failed(_, text):
            message = text
        case let ProviderError.notSupported(text):
            message = text
        default:
            return false
        }

        let lower = message.lowercased()
        if lower.contains("coding plan") {
            return lower.contains("no ")
                || lower.contains("not found")
                || lower.contains("没有")
                || lower.contains("订阅")
        }
        return lower.contains("额度窗口") || lower.contains("quota window")
    }

    /// Token Plan 的 JSON 是动态配额字段，例如 per5HourPercentage / per1WeekPercentage / per1MonthPercentage。
    static func parseTokenPlan(_ json: Any) throws -> ProviderSnapshot {
        guard let root = json as? [String: Any], !root.isEmpty else {
            throw ProviderError.notSupported(
                T("没有 Token Plan 配额数据", "No Token Plan quota data")
            )
        }
        if root["hasQuotaData"] as? Bool == false {
            throw ProviderError.notSupported(
                T("Token Plan 接口没有返回配额窗口", "Token Plan returned no quota windows")
            )
        }

        func window(_ key: String, _ kind: QuotaKind) -> QuotaWindow? {
            guard let ratio = (root[key + "Percentage"] as? NSNumber)?.doubleValue else { return nil }
            var reset = (root[key + "ResetTime"] as? NSNumber)?.doubleValue
            if let value = reset, value > 1_000_000_000_000 { reset = value / 1000 }
            return QuotaWindow(
                kind: kind,
                remainingPercent: min(max((1 - ratio) * 100, 0), 100),
                resetDate: reset.map { Date(timeIntervalSince1970: $0) }
            )
        }

        let quotas = [
            window("per5Hour", .fiveHour),
            window("per1Week", .weekly),
            window("per1Month", .monthly)
        ].compactMap { $0 }

        guard !quotas.isEmpty else {
            throw ProviderError.notSupported(
                T("Token Plan 没有可读取的额度窗口", "No Token Plan quota windows found")
            )
        }

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: quotas.sorted { $0.kind.sortOrder < $1.kind.sortOrder },
            planName: "Bailian Token Plan"
        )
    }

    static func parse(_ json: Any) throws -> ProviderSnapshot {
        guard let root = json as? [String: Any], !root.isEmpty else {
            throw ProviderError.notSupported(
                T(
                    "已登录，但该账号没有 Coding Plan 订阅；可在设置里填 AccessKey 读账户余额。",
                    "Signed in, but this account has no Coding Plan; enter an AccessKey in Settings to read the account balance."
                )
            )
        }

        func window(_ key: String, _ kind: QuotaKind) -> QuotaWindow? {
            guard let entry = root[key] as? [String: Any] else { return nil }
            var ratio = (entry["percentage"] as? NSNumber)?.doubleValue
            if ratio == nil,
               let used = (entry["usedQuota"] as? NSNumber)?.doubleValue,
               let total = (entry["totalQuota"] as? NSNumber)?.doubleValue,
               total > 0 {
                ratio = used / total
            }
            guard let ratio else { return nil }
            var reset = (entry["resetTime"] as? NSNumber)?.doubleValue
            if let value = reset, value > 1_000_000_000_000 { reset = value / 1000 }
            return QuotaWindow(
                kind: kind,
                remainingPercent: min(max((1 - ratio) * 100, 0), 100),
                resetDate: reset.map { Date(timeIntervalSince1970: $0) }
            )
        }

        let quotas = [
            window("per5Hour", .fiveHour),
            window("perWeek", .weekly),
            window("perBillMonth", .monthly)
        ].compactMap { $0 }

        guard !quotas.isEmpty else {
            throw ProviderError.notSupported(T("没有可读取的额度窗口", "No quota windows found"))
        }

        let plan = root["instanceType"] as? String
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: quotas,
            planName: plan.map { "Bailian Coding Plan · \($0)" } ?? "Bailian Coding Plan"
        )
    }
}

// MARK: - 腾讯云账户余额

struct TencentCloudCLIProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let json = try CLIExecutor.json(
            tool: "tccli",
            arguments: ["billing", "DescribeAccountBalance", "--cli-region", "ap-guangzhou", "--output", "json"],
            installHint: T(
                "先运行 pip install tccli，再执行 tccli configure。",
                "Run pip install tccli, then tccli configure."
            )
        )
        return try Self.parse(json)
    }

    static func parse(_ json: Any) throws -> ProviderSnapshot {
        guard let root = json as? [String: Any],
              let response = root["Response"] as? [String: Any] else {
            throw ProviderError.network(T("响应缺少 Response", "Response is missing"))
        }
        let real = (response["RealBalance"] as? NSNumber)?.doubleValue
            ?? (response["Balance"] as? NSNumber)?.doubleValue
        guard let real else {
            throw ProviderError.network(T("响应缺少余额字段", "Balance field is missing"))
        }
        let total = real / 100  // 腾讯返回单位：分
        let presentCents = (response["PresentAccountBalance"] as? NSNumber)?.doubleValue
        let cashCents = (response["CashAccountBalance"] as? NSNumber)?.doubleValue
        let present = presentCents.map { $0 / 100 }
        let cash = cashCents.map { $0 / 100 }

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: total,
                granted: present,
                toppedUp: cash,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "Tencent Cloud"
        )
    }
}


// MARK: - 华为云账户余额

struct HuaweiCloudCLIProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let json = try CLIExecutor.json(
            tool: "hcloud",
            arguments: ["BSS", "ShowCustomerAccountBalances", "--cli-region", "cn-north-1"],
            installHint: T(
                "先安装华为云 KooCLI，再执行 hcloud configure init。",
                "Install Huawei Cloud KooCLI, then run hcloud configure init."
            )
        )
        return try Self.parse(json)
    }

    static func parse(_ json: Any) throws -> ProviderSnapshot {
        guard let root = json as? [String: Any] else {
            throw ProviderError.network(T("响应不是 JSON 对象", "Response is not a JSON object"))
        }
        let balances = (root["account_balances"] as? [[String: Any]])
            ?? (root["accountBalances"] as? [[String: Any]])
            ?? []
        guard !balances.isEmpty else {
            throw ProviderError.notSupported(T("没有读到账户余额", "No account balance found"))
        }

        func amount(_ item: [String: Any]) -> Double? {
            if let value = item["amount"] as? NSNumber { return value.doubleValue }
            if let text = item["amount"] as? String { return Double(text) }
            return nil
        }
        func type(_ item: [String: Any]) -> Int? {
            (item["account_type"] as? NSNumber)?.intValue
                ?? (item["accountType"] as? NSNumber)?.intValue
        }

        var total = 0.0
        var granted = 0.0
        var hasGranted = false
        for item in balances {
            guard let value = amount(item) else { continue }
            switch type(item) {
            case 1: total += value
            case 5:
                total += value
                granted += value
                hasGranted = true
            default: break
            }
        }
        if total == 0 {
            total = balances.compactMap(amount).reduce(0, +)
        }

        let currency = (root["currency"] as? String) ?? "CNY"
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: currency,
                total: total,
                granted: hasGranted ? granted : nil,
                toppedUp: nil,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "Huawei Cloud"
        )
    }
}
