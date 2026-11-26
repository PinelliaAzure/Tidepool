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
            if days >= 10 {
                return L10n.isEnglish ? "\(Int(days)) days" : "\(Int(days)) 天"
            }
            return L10n.isEnglish
                ? String(format: "%.1f days", days)
                : String(format: "%.1f 天", days)
        }
        let hours = days * 24
        if hours >= 1 {
            return L10n.isEnglish
                ? String(format: "%.0f hours", hours)
                : String(format: "%.0f 小时", hours)
        }
        let minutes = hours * 60
        return L10n.isEnglish
            ? String(format: "%.0f min", minutes)
            : String(format: "%.0f 分钟", minutes)
    }

    /// 额度重置倒计时 → "2 小时 18 分后重置" / "resets in 2h 18m"。
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return T("已重置", "reset") }
        let short = countdownShort(to: date, now: now)
        return L10n.isEnglish ? "resets in \(short)" : short + "后重置"
    }

    /// 不带后缀的倒计时 → "8 小时 19 分" / "8h 19m"。
    static func countdownShort(to date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return T("即将", "soon") }
        let totalMinutes = Int((interval / 60).rounded(.up))
        if totalMinutes >= 1440 {
            let days = totalMinutes / 1440
            let hours = (totalMinutes % 1440) / 60
            if L10n.isEnglish {
                return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
            }
            return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
        }
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if L10n.isEnglish {
                return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
            }
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        return L10n.isEnglish ? "\(totalMinutes)m" : "\(totalMinutes) 分钟"
    }

    /// "11月26日 14:30"
    static func resetDateText(_ date: Date) -> String {
        let formatter = L10n.isEnglish ? englishDateFormatter : chineseDateFormatter
        return formatter.string(from: date)
    }

    /// 紧凑 token 数：1.2M / 86.2k / 932
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.2fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", value / 1_000)
        default:
            return "\(count)"
        }
    }

    /// 图表横轴："11/22"（中英通用，省空间）
    static func axisDate(_ date: Date) -> String {
        axisDateFormatter.string(from: date)
    }

    /// 美元估算：$1.23 / <$0.01
    static func usd(_ value: Double) -> String {
        if value > 0 && value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", value)
    }

    /// "刚刚" / "10 分钟前"。
    static func relative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        if abs(now.timeIntervalSince(date)) < 60 {
            return T("刚刚", "just now")
        }
        let formatter = L10n.isEnglish ? englishRelativeFormatter : chineseRelativeFormatter
        return formatter.localizedString(for: date, relativeTo: now)
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

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let chineseRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let englishRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let chineseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let englishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}
