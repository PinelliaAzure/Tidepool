import CryptoKit
import Foundation

/// 云厂商 AK/SK（存为 Keychain 里的 JSON，不落配置文件）。
struct CloudCredentials: Codable, Equatable {
    var secretId: String
    var secretKey: String

    static func decode(_ raw: String?) -> CloudCredentials? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CloudCredentials.self, from: data)
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 腾讯云 TC3-HMAC-SHA256

struct TencentCloudProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        guard let credentials = CloudCredentials.decode(apiKey),
              !credentials.secretId.isEmpty,
              !credentials.secretKey.isEmpty else {
            throw ProviderError.notSupported(
                T("请填写腾讯云 SecretId 和 SecretKey", "Enter your Tencent Cloud SecretId and SecretKey")
            )
        }

        let host = "billing.tencentcloudapi.com"
        let service = "billing"
        let action = "DescribeAccountBalance"
        let version = "2018-07-09"
        let region = "ap-guangzhou"
        let payload = "{}"

        let timestamp = Int(Date().timeIntervalSince1970)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))

        let signedHeaders = "content-type;host"
        let signature = Self.signature(
            secretKey: credentials.secretKey,
            date: date,
            service: service,
            timestamp: timestamp,
            payload: payload,
            host: host
        )

        let authorization = "TC3-HMAC-SHA256 Credential=\(credentials.secretId)/\(date)/\(service)/tc3_request, "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: URL(string: "https://\(host)")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = Data(payload.utf8)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network(T("无效响应", "Invalid response"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.invalidKey
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ProviderError.network(T("响应不是 JSON", "Response is not JSON"))
        }
        if let root = json as? [String: Any],
           let responseObject = root["Response"] as? [String: Any],
           let error = responseObject["Error"] as? [String: Any],
           let message = error["Message"] as? String {
            throw ProviderError.notSupported(message)
        }
        return try TencentCloudBalanceParser.parse(json)
    }

    /// TC3 签名：中间派生密钥必须保持二进制，不能转成十六进制字符串。
    static func signature(
        secretKey: String,
        date: String,
        service: String,
        timestamp: Int,
        payload: String,
        host: String
    ) -> String {
        // 与腾讯云官方 SDK 完全一致：只签 content-type 和 host。
        let canonicalHeaders = "content-type:application/json; charset=utf-8\n"
            + "host:\(host)\n"
        let signedHeaders = "content-type;host"
        let canonicalRequest = "POST\n/\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(sha256Hex(payload))"
        let stringToSign = "TC3-HMAC-SHA256\n\(timestamp)\n\(date)/\(service)/tc3_request\n\(sha256Hex(canonicalRequest))"

        let secretDate = hmacData(key: Data(("TC3" + secretKey).utf8), data: date)
        let secretService = hmacData(key: secretDate, data: service)
        let secretSigning = hmacData(key: secretService, data: "tc3_request")
        return hex(hmacData(key: secretSigning, data: stringToSign))
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacData(key: Data, data: String) -> Data {
        let code = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))
        return Data(code)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 华为云 SDK-HMAC-SHA256

struct HuaweiCloudProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        guard let credentials = CloudCredentials.decode(apiKey),
              !credentials.secretId.isEmpty,
              !credentials.secretKey.isEmpty else {
            throw ProviderError.notSupported(
                T("请填写华为云 Access Key 和 Secret Key", "Enter your Huawei Cloud Access Key and Secret Key")
            )
        }

        let host = "bss.myhuaweicloud.com"
        let path = "/v2/accounts/customer-accounts/balances"
        let timestamp = huaweiDate()

        let signature = Self.signature(
            secretKey: credentials.secretKey,
            path: path,
            host: host,
            timestamp: timestamp
        )

        let authorization = "SDK-HMAC-SHA256 Access=\(credentials.secretId), "
            + "SignedHeaders=content-type;host;x-sdk-date, Signature=\(signature)"

        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(timestamp, forHTTPHeaderField: "X-Sdk-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network(T("无效响应", "Invalid response"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.invalidKey
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ProviderError.network(T("响应不是 JSON", "Response is not JSON"))
        }
        return try HuaweiCloudBalanceParser.parse(json)
    }

    /// 华为云 SDK-HMAC-SHA256。官方 SDK 的 CanonicalURI 会补结尾 `/`，
    /// 但实际请求 URL 不带这个斜杠，两者不能混用。
    static func signature(
        secretKey: String,
        path: String,
        host: String,
        timestamp: String,
        contentType: String = "application/json"
    ) -> String {
        let canonicalPath = path.hasSuffix("/") ? path : path + "/"
        let signedHeaders = "content-type;host;x-sdk-date"
        let canonicalHeaders = "content-type:\(contentType)\n"
            + "host:\(host)\n"
            + "x-sdk-date:\(timestamp)\n"
        let canonicalRequest = "GET\n\(canonicalPath)\n\n\(canonicalHeaders)\n\(signedHeaders)\n"
            + sha256Hex("")
        let stringToSign = "SDK-HMAC-SHA256\n\(timestamp)\n\(sha256Hex(canonicalRequest))"
        return hmacHex(key: secretKey, data: stringToSign)
    }

    private func huaweiDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacHex(key: String, data: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: symmetricKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 阿里云账户余额（BSS + RPC 签名）

struct AlibabaCloudProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        guard let credentials = CloudCredentials.decode(apiKey),
              !credentials.secretId.isEmpty,
              !credentials.secretKey.isEmpty else {
            throw ProviderError.notSupported(
                T("请填写阿里云 AccessKey ID 和 AccessKey Secret", "Enter your Alibaba Cloud AccessKey ID and Secret")
            )
        }

        let params: [(String, String)] = [
            ("AccessKeyId", credentials.secretId),
            ("Action", "QueryAccountBalance"),
            ("Format", "JSON"),
            ("SignatureMethod", "HMAC-SHA1"),
            ("SignatureNonce", UUID().uuidString),
            ("SignatureVersion", "1.0"),
            ("Timestamp", timestamp()),
            ("Version", "2017-12-14")
        ]

        let canonical = Self.canonicalQuery(params)
        let signature = Self.signature(secretKey: credentials.secretKey, canonicalQuery: canonical)

        let urlString = "https://business.aliyuncs.com/?\(canonical)&Signature=\(Self.percentEncode(signature))"
        guard let url = URL(string: urlString) else {
            throw ProviderError.network(T("无效的请求地址", "Invalid request URL"))
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network(T("无效响应", "Invalid response"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.invalidKey
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode)
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ProviderSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.network(T("响应不是 JSON", "Response is not JSON"))
        }
        if let success = root["Success"] as? Bool, success == false {
            let message = (root["Message"] as? String) ?? (root["Code"] as? String) ?? T("读取失败", "Request failed")
            throw ProviderError.notSupported(message)
        }
        guard let payload = root["Data"] as? [String: Any] else {
            throw ProviderError.network(T("响应缺少 Data", "Response is missing Data"))
        }

        func number(_ key: String) -> Double? {
            if let value = payload[key] as? NSNumber { return value.doubleValue }
            if let text = payload[key] as? String { return Double(text) }
            return nil
        }

        let total = number("AvailableAmount") ?? number("AvailableCashAmount") ?? 0
        let cash = number("AvailableCashAmount")
        let currency = (payload["Currency"] as? String) ?? "CNY"

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: currency,
                total: total,
                granted: nil,
                toppedUp: cash,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "Alibaba Cloud"
        )
    }

    /// RPC 风格签名：参数按 key 排序后 RFC3986 编码，再对整串签名。
    static func canonicalQuery(_ params: [(String, String)]) -> String {
        params
            .sorted { $0.0 < $1.0 }
            .map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }
            .joined(separator: "&")
    }

    static func signature(secretKey: String, canonicalQuery: String) -> String {
        let stringToSign = "GET&%2F&\(percentEncode(canonicalQuery))"
        let key = "\(secretKey)&"
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: symmetricKey)
        return Data(code).base64EncodedString()
    }

    static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }

}
