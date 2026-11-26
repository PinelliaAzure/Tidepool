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

        let canonicalHeaders = "content-type:application/json; charset=utf-8\nhost:\(host)\n"
        let signedHeaders = "content-type;host"
        let hashedPayload = sha256Hex(payload)
        let canonicalRequest = "POST\n/\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(hashedPayload)"
        let stringToSign = "TC3-HMAC-SHA256\n\(timestamp)\n\(date)/\(service)/tc3_request\n\(sha256Hex(canonicalRequest))"

        let secretDate = hmac(key: "TC3\(credentials.secretKey)", data: date)
        let secretService = hmac(key: secretDate, data: service)
        let secretSigning = hmac(key: secretService, data: "tc3_request")
        let signature = hmac(key: secretSigning, data: stringToSign)

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
        return try TencentCloudCLIProvider.parse(json)
    }

    private func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func hmac(key: String, data: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: symmetricKey)
        return code.map { String(format: "%02x", $0) }.joined()
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

        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-sdk-date:\(timestamp)\n"
        let signedHeaders = "content-type;host;x-sdk-date"
        let canonicalRequest = "GET\n\(path)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(sha256Hex(""))"
        let stringToSign = "SDK-HMAC-SHA256\n\(timestamp)\n\(sha256Hex(canonicalRequest))"
        let signature = hmac(key: credentials.secretKey, data: stringToSign)

        let authorization = "SDK-HMAC-SHA256 Access=\(credentials.secretId), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"

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
        return try HuaweiCloudCLIProvider.parse(json)
    }

    private func huaweiDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    private func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func hmac(key: String, data: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: symmetricKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}
