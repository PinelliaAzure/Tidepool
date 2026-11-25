import AppKit
import SwiftUI

// MARK: - Provider 定义

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case deepseek
    case moonshot
    case kimiCode
    case glm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .moonshot: return "Kimi"
        case .kimiCode: return "Kimi Code"
        case .glm: return "GLM"
        }
    }

    /// 品牌主色（用于状态点、胶囊选中态、水位图等强调场景）。
    var brandHex: UInt32 {
        switch self {
        case .deepseek: return 0x4D6BFE
        case .moonshot: return 0x8B5CF6
        case .kimiCode: return 0x8B5CF6
        case .glm: return 0x14B8A6
        }
    }

    var brandColor: Color { Color(hex: brandHex) }
    var nsBrandColor: NSColor { NSColor(hex: brandHex) }

    /// M0 可直接添加的 Provider；其余接口在 M1 接入。
    var isConfigurable: Bool {
        switch self {
        case .deepseek, .moonshot: return true
        case .kimiCode, .glm: return false
        }
    }

    var platformURL: URL {
        switch self {
        case .deepseek: return URL(string: "https://platform.deepseek.com")!
        case .moonshot: return URL(string: "https://platform.moonshot.cn")!
        case .kimiCode: return URL(string: "https://platform.kimi.com")!
        case .glm: return URL(string: "https://open.bigmodel.cn")!
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .deepseek: return URL(string: "https://api.deepseek.com")!
        case .moonshot: return URL(string: "https://api.moonshot.cn")!
        case .kimiCode: return URL(string: "https://api.kimi.com")!
        case .glm: return URL(string: "https://open.bigmodel.cn")!
        }
    }
}

// MARK: - 账户

struct ProviderAccount: Codable, Identifiable, Equatable {
    var id: UUID
    var provider: ProviderID
    var name: String
    var enabled: Bool
    var intervalSeconds: Int
    var baseURL: URL?
    var sortOrder: Int
    var createdAt: Date

    init(
        provider: ProviderID,
        name: String,
        enabled: Bool = true,
        intervalSeconds: Int = 300,
        baseURL: URL? = nil,
        sortOrder: Int = 0,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.baseURL = baseURL
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, name, enabled, intervalSeconds, baseURL, sortOrder, createdAt
    }

    /// 兼容后续字段演进：缺失字段回退到默认值。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try container.decode(ProviderID.self, forKey: .provider)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? provider.displayName
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        intervalSeconds = try container.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 300
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - 快照与采样

struct BalanceSnapshot: Codable, Equatable {
    var currency: String
    var total: Double
    var granted: Double?
    var toppedUp: Double?
    var isAvailable: Bool
}

enum QuotaKind: String, Codable {
    case fiveHour
    case weekly
    case monthly
}

struct QuotaWindow: Codable, Equatable, Identifiable {
    var kind: QuotaKind
    var remainingPercent: Double
    var resetDate: Date?
    var id: String { kind.rawValue }
}

/// 一次刷新得到的完整快照：余额与套餐额度可并存。
struct ProviderSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var balance: BalanceSnapshot?
    var quotas: [QuotaWindow]
}

/// 余额水位的历史采样点，用于潮汐图与 runway 计算。
struct SamplePoint: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var value: Double

    init(date: Date, value: Double) {
        self.id = UUID()
        self.date = date
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        value = try container.decode(Double.self, forKey: .value)
    }
}

struct AccountState: Equatable {
    var isRefreshing = false
    var lastSuccess: Date?
    var lastError: String?
}
