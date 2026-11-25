import Foundation

enum MoneyStyle {
    /// 菜单栏：紧凑（¥42.50 / ¥1,284 / ¥12.8k）
    case menuBar
    /// 面板 Hero：完整两位小数（¥42.50）
    case hero
    /// 图表轴：整数，必要时 k
    case axis
}

/// 展示层格式化：金额、百分比、时长、相对时间。
enum TideFormatter {
    static func currencySymbol(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default: return currencyCode + " "
        }
    }

    /// 含货币符号的金额。
    static func money(_ value: Double, currency currencyCode: String, style: MoneyStyle) -> String {
        currencySymbol(for: currencyCode) + amount(value, style: style)
    }

    /// 纯数字部分（等宽数字场景由调用方设置字体）。
    static func amount(_ value: Double, style: MoneyStyle) -> String {
        switch style {
        case .menuBar:
            if abs(value) >= 10_000 {
                return String(format: "%.1fk", value / 1_000)
            }
            if abs(value) >= 1_000 {
                return grouped(value, fractionDigits: 0)
            }
            return grouped(value, fractionDigits: 2)
        case .hero:
            return grouped(value, fractionDigits: 2)
        case .axis:
            if abs(value) >= 10_000 {
                return String(format: "%.0fk", value / 1_000)
            }
            return grouped(value, fractionDigits: 0)
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// runway 天数 → "13 天" / "3.4 天" / "8 小时" / "25 分钟"。
    static func duration(days: Double) -> String {
        if days >= 1 {
            return days >= 10 ? "\(Int(days)) 天" : String(format: "%.1f 天", days)
        }
        let hours = days * 24
        if hours >= 1 {
            return String(format: "%.0f 小时", hours)
        }
        return String(format: "%.0f 分钟", hours * 60)
    }

    /// "10 分钟前"；一分钟内显示"刚刚"。
    static func relative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        if abs(now.timeIntervalSince(date)) < 60 {
            return "刚刚"
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - Private

    private static func grouped(_ value: Double, fractionDigits: Int) -> String {
        // 每次新建 formatter：测试并发调用时不共享可变状态
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        return formatter
    }()
}
