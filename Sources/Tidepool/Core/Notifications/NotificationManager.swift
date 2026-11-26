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
    private let storageKey = "alerts.fired"

    private var fired: Set<String> {
        get { Set(defaults.stringArray(forKey: storageKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: storageKey) }
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
            keys.remove("balance-\(account.id.uuidString)")
        }

        let events = AlertPlanner.events(
            account: account,
            snapshot: snapshot,
            includeReset: includeReset
        )
        for event in events where !keys.contains(event.key) {
            keys.insert(event.key)
            post(title: event.title, body: event.body)
        }

        // 控制持久化体积
        if keys.count > 300 {
            keys = Set(Array(keys).suffix(200))
        }
        fired = keys
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
