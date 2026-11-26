import AppKit
import SwiftUI

// MARK: - Provider 定义

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case deepseek
    case moonshot
    case kimiCode
    case glm
    case openrouter
    case siliconFlow
    case volcengine
    case alibaba
    case tencent
    case huawei
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .moonshot: return "Kimi"
        case .kimiCode: return "Kimi Code"
        case .glm: return "GLM"
        case .openrouter: return "OpenRouter"
        case .siliconFlow: return "SiliconFlow"
        case .volcengine: return T("火山方舟", "Volcengine Ark")
        case .alibaba: return T("阿里云百炼", "Alibaba Model Studio")
        case .tencent: return T("腾讯云", "Tencent Cloud")
        case .huawei: return T("华为云", "Huawei Cloud")
        case .custom: return T("自定义", "Custom")
        }
    }

    /// 品牌主色（用于状态点、胶囊选中态、水位图等强调场景）。
    var brandHex: UInt32 {
        switch self {
        case .deepseek: return 0x4D6BFE
        case .moonshot: return 0x8B5CF6
        case .kimiCode: return 0x8B5CF6
        case .glm: return 0x14B8A6
        case .openrouter: return 0x6C5CE7
        case .siliconFlow: return 0x5B5CF5
        case .volcengine: return 0x1664FF
        case .alibaba: return 0xFF6A00
        case .tencent: return 0x006EFF
        case .huawei: return 0xCF0A2C
        case .custom: return 0x8E8E93
        }
    }

    var brandColor: Color { Color(hex: brandHex) }
    var nsBrandColor: NSColor { NSColor(hex: brandHex) }

    /// M1：两类额度渠道已接入。
    var isConfigurable: Bool { true }

    /// 渠道类型说明（设置窗口用）。
    var kindDescription: String {
        switch self {
        case .deepseek: return T("开放平台 API 余额", "API balance")
        case .moonshot: return T("开放平台 API 余额", "API balance")
        case .kimiCode: return T("Kimi For Coding 套餐额度", "Kimi For Coding quota")
        case .glm: return T("GLM Coding Plan 额度", "GLM Coding Plan quota")
        case .openrouter: return T("API 余额（USD）", "API credits (USD)")
        case .siliconFlow: return T("API 余额（CNY）", "API balance (CNY)")
        case .volcengine: return T("Coding Plan 额度（arkcli）", "Coding Plan quota (arkcli)")
        case .alibaba: return T("Coding Plan 额度（bl）", "Coding Plan quota (bl)")
        case .tencent: return T("账户余额（tccli）", "Account balance (tccli)")
        case .huawei: return T("账户余额（hcloud）", "Account balance (hcloud)")
        case .custom: return T("只读 JSON 接口", "Read-only JSON API")
        }
    }

    /// 套餐额度型 Provider：面板展示圆环而不是余额。
    var isQuotaProvider: Bool {
        switch self {
        case .kimiCode, .glm: return true
        case .deepseek, .moonshot, .openrouter, .siliconFlow, .volcengine, .alibaba, .tencent, .huawei, .custom:
            return false
        }
    }

    var platformURL: URL {
        switch self {
        case .deepseek: return URL(string: "https://platform.deepseek.com")!
        case .moonshot: return URL(string: "https://platform.moonshot.cn")!
        case .kimiCode: return URL(string: "https://platform.kimi.com")!
        case .glm: return URL(string: "https://open.bigmodel.cn")!
        case .openrouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .siliconFlow: return URL(string: "https://cloud.siliconflow.cn/account/ak")!
        case .volcengine: return URL(string: "https://console.volcengine.com/ark")!
        case .alibaba: return URL(string: "https://bailian.console.aliyun.com")!
        case .tencent: return URL(string: "https://console.cloud.tencent.com/billing")!
        case .huawei: return URL(string: "https://console.huaweicloud.com/billing")!
        case .custom: return URL(string: "https://github.com/PinelliaAzure/Tidepool")!
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .deepseek: return URL(string: "https://api.deepseek.com")!
        case .moonshot: return URL(string: "https://api.moonshot.cn")!
        case .kimiCode: return URL(string: "https://api.kimi.com")!
        case .glm: return URL(string: "https://open.bigmodel.cn")!
        case .openrouter: return URL(string: "https://openrouter.ai")!
        case .siliconFlow: return URL(string: "https://api.siliconflow.cn")!
        case .volcengine: return URL(string: "https://ark.cn-beijing.volces.com")!
        case .alibaba: return URL(string: "https://dashscope.aliyuncs.com")!
        case .tencent: return URL(string: "https://billing.tencentcloudapi.com")!
        case .huawei: return URL(string: "https://bss.myhuaweicloud.com")!
        case .custom: return URL(string: "https://example.com")!
        }
    }

    /// 首次引导只展示无需额外 CLI 的渠道。
    static var onboardingCases: [ProviderID] {
        allCases.filter { !$0.usesCLI && $0 != .custom }
    }

    /// 依赖本机官方 CLI（登录后读取额度/余额），不保存 API Key。
    var usesCLI: Bool {
        switch self {
        case .volcengine, .alibaba, .tencent, .huawei: return true
        default: return false
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
    var custom: CustomEndpointConfig?

    init(
        provider: ProviderID,
        name: String,
        enabled: Bool = true,
        intervalSeconds: Int = 300,
        baseURL: URL? = nil,
        sortOrder: Int = 0,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        custom: CustomEndpointConfig? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.baseURL = baseURL
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.custom = custom
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, name, enabled, intervalSeconds, baseURL, sortOrder, createdAt, custom
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
        custom = try container.decodeIfPresent(CustomEndpointConfig.self, forKey: .custom)
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

enum QuotaKind: String, Codable, CaseIterable {
    case fiveHour
    case weekly
    case monthly
    case custom

    var displayName: String {
        switch self {
        case .fiveHour: return T("5 小时", "5-hour")
        case .weekly: return T("本周", "Weekly")
        case .monthly: return T("本月", "Monthly")
        case .custom: return T("自定义", "Custom")
        }
    }

    /// 该额度窗口的时长，用于「时间进度 vs 用量进度」节奏判断。
    var windowLength: TimeInterval? {
        switch self {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 86_400
        case .monthly: return 30 * 86_400
        case .custom: return nil
        }
    }

    var sortOrder: Int {
        switch self {
        case .fiveHour: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .custom: return 3
        }
    }
}

struct QuotaWindow: Codable, Equatable, Identifiable {
    var kind: QuotaKind
    var remainingPercent: Double
    var resetDate: Date?
    var id: String { kind.rawValue }

    var remainingFraction: Double {
        min(max(remainingPercent / 100, 0), 1)
    }
}

/// 一次刷新得到的完整快照：余额与套餐额度可并存。
struct ProviderSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var balance: BalanceSnapshot?
    var quotas: [QuotaWindow]
    /// 套餐名称，如 "GLM Coding Plan · Pro" / "Kimi Code"。
    var planName: String?

    var tightestQuota: QuotaWindow? {
        quotas.min { $0.remainingPercent < $1.remainingPercent }
    }

    var sortedQuotas: [QuotaWindow] {
        quotas.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
    }
}

/// 菜单栏展示策略。
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case single
    case all
    case tightest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return T("当前 Provider", "Current provider")
        case .all: return T("全部（紧凑）", "All (compact)")
        case .tightest: return T("最紧张的一项", "Tightest quota")
        }
    }
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

/// 额度剩余百分比的历史采样，用于「额度走势」。
struct QuotaSamplePoint: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var kind: QuotaKind
    var remainingPercent: Double

    init(date: Date, kind: QuotaKind, remainingPercent: Double) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.remainingPercent = remainingPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(QuotaKind.self, forKey: .kind)
        remainingPercent = try container.decode(Double.self, forKey: .remainingPercent)
    }
}

struct AccountState: Equatable {
    var isRefreshing = false
    var lastSuccess: Date?
    var lastError: String?
}
