import Foundation
import UserNotifications

/// 发送系统通知并对事件去重：
/// - 余额跌破阈值提醒一次，回升到 1.2 倍阈值以上才重新武装
/// - 每个额度窗口（按重置时间区分）的低额度 / 重置提醒各只发一次
/// - 提醒记录持久化，重启不重复打扰
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let defaults = UserDefaults.standard
    private let storageKey = "alerts.fired.v2"
    private let legacyKey = "alerts.fired"

    /// 去重记录：key → 最近一次触发时间。带时间戳才能在裁剪时保留最新的记录。
    private var fired: [String: Date] {
        get {
            if let stored = defaults.dictionary(forKey: storageKey) {
                var result: [String: Date] = [:]
                for (key, value) in stored {
                    if let date = value as? Date {
                        result[key] = date
                    } else if let interval = value as? Double {
                        result[key] = Date(timeIntervalSince1970: interval)
                    }
                }
                return result
            }
            // 迁移旧版无时间戳的集合：视为最旧，裁剪时优先清理。
            if let legacy = defaults.stringArray(forKey: legacyKey) {
                return Dictionary(uniqueKeysWithValues: legacy.map { ($0, Date.distantPast) })
            }
            return [:]
        }
        set {
            defaults.set(newValue, forKey: storageKey)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    func requestAuthorization() {
        // 非 .app 包（swift run / 测试）没有 bundle id，跳过避免异常
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(
        account: ProviderAccount,
        snapshot: ProviderSnapshot,
        enabled: Bool,
        includeReset: Bool
    ) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }

        var keys = fired

        // 余额恢复后重新武装低余额提醒
        if let balance = snapshot.balance,
           balance.total > AppStore.lowBalanceThreshold * 1.2 {
            keys["balance-\(account.id.uuidString)"] = nil
        }

        let events = AlertPlanner.events(
            account: account,
            snapshot: snapshot,
            includeReset: includeReset
        )
        for event in events where keys[event.key] == nil {
            keys[event.key] = Date()
            post(title: event.title, body: event.body)
        }

        fired = Self.trimmed(keys)
    }

    /// 去重记录只保留最近触发的 200 条，避免 UserDefaults 无限增长。
    static func trimmed(_ keys: [String: Date], limit: Int = 200) -> [String: Date] {
        guard keys.count > limit else { return keys }
        let newest = keys.sorted { $0.value > $1.value }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
