import Foundation

/// 读取硅基流动控制台（cloud.siliconflow.cn）的余额。
/// 控制台接口没有公开文档，返回结构可能变化；解析器保持宽松，失败时给出可操作的提示。
struct SiliconFlowConsoleProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        guard let session = SiliconFlowSession.decode(apiKey) else {
            throw ProviderError.notSupported(
                T(
                    "还没有连接硅基流动控制台。请在设置里点击「在 Tidepool 中登录」或「从 Safari 读取」。",
                    "No SiliconFlow console session yet. In Settings, use “Sign in with Tidepool” or “Read from Safari”."
                )
            )
        }
        return try await SiliconFlowConsoleClient().fetch(session: session)
    }
}

struct SiliconFlowConsoleClient {
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// 手动设置 Cookie 头，避免 URLSession 自己的 Cookie 存储混入其他会话。
    private let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    func fetch(session: SiliconFlowSession) async throws -> ProviderSnapshot {
        var failures: [String] = []

        do {
            return try await userInfo(session: session, subjectID: session.subjectID)
        } catch let error as ConsoleError {
            if error == .signedOut { throw Self.signedOutError }
            failures.append(error.description)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let subject = try await subjectID(session: session) ?? session.subjectID
            return try await wallet(session: session, subjectID: subject)
        } catch let error as ConsoleError {
            if error == .signedOut { throw Self.signedOutError }
            failures.append(error.description)
        } catch {
            failures.append(error.localizedDescription)
        }

        let detail = failures.joined(separator: " · ")
        throw ProviderError.notSupported(
            T(
                "硅基流动控制台读取失败\(detail.isEmpty ? "" : "：\(detail)")。请重新连接登录态；如果仍失败，可能是控制台接口有变化。",
                "Could not read the SiliconFlow console\(detail.isEmpty ? "" : ": \(detail)"). Reconnect the session; if it still fails, the console API may have changed."
            )
        )
    }

    // MARK: - 控制台接口

    private func userInfo(session: SiliconFlowSession, subjectID: String?) async throws -> ProviderSnapshot {
        var request = baseRequest(
            url: URL(string: "https://cloud.siliconflow.cn/biz-server/api/v1/user/info")!,
            session: session
        )
        if let subjectID, !subjectID.isEmpty {
            request.setValue(subjectID, forHTTPHeaderField: "X-Subject-ID")
        }

        let (data, response) = try await urlSession.data(for: request)
        try validate(response)

        do {
            return try Self.parseUserInfo(data)
        } catch {
            if let http = response as? HTTPURLResponse,
               let returned = http.value(forHTTPHeaderField: "x-subject-id"),
               !returned.isEmpty,
               returned != subjectID {
                var retry = request
                retry.setValue(returned, forHTTPHeaderField: "X-Subject-ID")
                let (retryData, retryResponse) = try await urlSession.data(for: retry)
                try validate(retryResponse)
                return try Self.parseUserInfo(retryData)
            }
            throw error
        }
    }

    private func wallet(session: SiliconFlowSession, subjectID: String?) async throws -> ProviderSnapshot {
        var request = baseRequest(
            url: URL(string: "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek")!,
            session: session
        )
        if let subjectID, !subjectID.isEmpty {
            request.setValue(subjectID, forHTTPHeaderField: "X-Subject-ID")
        }

        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return try Self.parseWallet(data)
    }

    private func subjectID(session: SiliconFlowSession) async throws -> String? {
        let request = baseRequest(
            url: URL(string: "https://cloud.siliconflow.cn/me/expensebill")!,
            session: session,
            accept: "text/html,application/xhtml+xml"
        )
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConsoleError.malformed("无效响应")
        }
        if http.url?.host == "account.siliconflow.cn" || http.statusCode == 401 {
            throw ConsoleError.signedOut
        }
        guard (200..<400).contains(http.statusCode) else {
            throw ConsoleError.http(http.statusCode)
        }
        let value = http.value(forHTTPHeaderField: "x-subject-id")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    private func baseRequest(
        url: URL,
        session: SiliconFlowSession,
        accept: String = "application/json, text/plain, */*"
    ) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(session.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("https://cloud.siliconflow.cn/me/expensebill", forHTTPHeaderField: "Referer")
        request.setValue("https://cloud.siliconflow.cn", forHTTPHeaderField: "Origin")
        request.setValue(session.userAgent ?? Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ConsoleError.malformed("无效响应")
        }
        if http.url?.host == "account.siliconflow.cn" || http.statusCode == 401 {
            throw ConsoleError.signedOut
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ConsoleError.http(http.statusCode)
        }
    }

    // MARK: - 解析

    static func parseUserInfo(_ data: Data) throws -> ProviderSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConsoleError.malformed("响应不是 JSON")
        }
        if let code = root["code"] as? Int, code != 20000 {
            throw ConsoleError.malformed("code \(code)")
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw ConsoleError.malformed("缺少 data")
        }

        func amount(_ key: String) -> Double? {
            if let value = payload[key] as? NSNumber { return value.doubleValue }
            if let text = payload[key] as? String { return Double(text) }
            return nil
        }

        guard let total = amount("totalBalance") ?? amount("balance") else {
            throw ConsoleError.malformed("缺少余额字段")
        }
        let toppedUp = amount("chargeBalance")

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: total,
                granted: nil,
                toppedUp: toppedUp,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "SiliconFlow"
        )
    }

    static func parseWallet(_ data: Data) throws -> ProviderSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConsoleError.malformed("响应不是 JSON")
        }
        if let code = root["code"] as? Int, code != 20000 {
            throw ConsoleError.malformed("code \(code)")
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw ConsoleError.malformed("缺少 data")
        }

        // 控制台钱包金额是 10^-12 CNY 的整数，例如 "12340000000000" = 12.34 CNY。
        if let financial = payload["financialInfo"] as? [String: Any],
           let raw = financial["balance"] as? String,
           let scaled = Double(raw) {
            let total = scaled / 1_000_000_000_000
            return snapshot(total: total, toppedUp: nil)
        }
        if let raw = payload["balance"] as? String, let total = Double(raw) {
            return snapshot(total: total, toppedUp: nil)
        }
        if let raw = payload["balance"] as? NSNumber {
            return snapshot(total: raw.doubleValue, toppedUp: nil)
        }
        throw ConsoleError.malformed("缺少余额字段")
    }

    private static func snapshot(total: Double, toppedUp: Double?) -> ProviderSnapshot {
        ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: total,
                granted: nil,
                toppedUp: toppedUp,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "SiliconFlow"
        )
    }

    static var signedOutError: ProviderError {
        .notSupported(
            T(
                "硅基流动登录态已过期，请到设置里重新连接控制台。",
                "Your SiliconFlow session has expired. Reconnect the console in Settings."
            )
        )
    }
}

private enum ConsoleError: Error, Equatable {
    case signedOut
    case malformed(String)
    case http(Int)

    var description: String {
        switch self {
        case .signedOut:
            return T("登录态已过期", "Session expired")
        case .malformed(let message):
            return message
        case .http(let code):
            return "HTTP \(code)"
        }
    }
}
