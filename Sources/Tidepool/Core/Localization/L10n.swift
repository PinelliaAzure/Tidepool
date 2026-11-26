import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.t("跟随系统", "System")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 轻量双语：所有界面文案用 `T("中文", "English")`。
/// 语言切换后重启生效，避免在运行期重建整个 AppKit/SwiftUI 树。
enum L10n {
    /// 测试中固定语言，避免依赖机器 locale。
    static var overrideEnglish: Bool?

    static var isEnglish: Bool {
        if let overrideEnglish { return overrideEnglish }
        if let env = ProcessInfo.processInfo.environment["TIDEPOOL_LANG"] {
            return env.lowercased().hasPrefix("en")
        }
        switch Prefs.language {
        case .en:
            return true
        case .zh:
            return false
        case .system:
            let code = Locale.preferredLanguages.first ?? "en"
            return !code.hasPrefix("zh")
        }
    }

    static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    static var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "zh_CN")
    }
}

/// 简写，读起来更接近普通字符串。
func T(_ zh: String, _ en: String) -> String {
    L10n.t(zh, en)
}
