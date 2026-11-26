import Foundation

/// 硅基流动控制台登录态。Cookie 只存钥匙串，也只发给 cloud.siliconflow.cn。
struct SiliconFlowSession: Codable, Equatable {
    var cookie: String
    var subjectID: String?
    var source: String
    var savedAt: Date
    var userAgent: String?

    private static let prefix = "sf-session:"

    static func decode(_ raw: String?) -> SiliconFlowSession? {
        guard let raw, raw.hasPrefix(prefix) else { return nil }
        let encoded = String(raw.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(SiliconFlowSession.self, from: data)
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return Self.prefix + data.base64EncodedString()
    }
}
