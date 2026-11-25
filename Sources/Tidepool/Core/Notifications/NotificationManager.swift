import Foundation
import UserNotifications

/// 低余额 / 低额度提醒：
/// - 余额跌破阈值时提醒一次，回升到 1.2 倍阈值以上才重新武装
/// - 每个额度窗口（按重置时间区分）只提醒一次
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

    func evaluate(account: ProviderAccount, snapshot: ProviderSnapshot, enabled: Bool) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }

        var keys = fired

        if let balance = snapshot.balance {
            let key = "balance-\(account.id.uuidString)"
            let belowThreshold = balance.isAvailable && balance.total <= AppStore.lowBalanceThreshold
            if belowThreshold {
                if !keys.contains(key) {
                    keys.insert(key)
                    post(
                        title: "\(account.name) 余额偏低",
                        body: "当前可用 \(TideFormatter.money(balance.total, currency: balance.currency, style: .hero))，记得及时充值。"
                    )
                }
            } else if balance.total > AppStore.lowBalanceThreshold * 1.2 {
                keys.remove(key)
            }
        }

        for quota in snapshot.quotas where quota.remainingPercent <= 10 {
            let cycle = quota.resetDate.map { String(Int($0.timeIntervalSince1970)) } ?? "static"
            let key = "quota-\(account.id.uuidString)-\(quota.kind.rawValue)-\(cycle)"
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            let resetNote = quota.resetDate.map { "，\(TideFormatter.countdown(to: $0))" } ?? ""
            post(
                title: "\(account.name) 额度不足",
                body: "\(quota.kind.displayName)额度剩余 \(TideFormatter.percent(quota.remainingPercent))\(resetNote)。"
            )
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
