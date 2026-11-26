import Foundation

struct AlertEvent: Equatable {
    var key: String
    var title: String
    var body: String
}

/// 纯逻辑：给定账户快照，决定应该发哪些提醒。
/// 去重 key 由 NotificationManager 持久化，这里只负责生成事件。
enum AlertPlanner {
    static let resetWindow: TimeInterval = 3600

    static func events(
        account: ProviderAccount,
        snapshot: ProviderSnapshot,
        now: Date = Date(),
        lowBalanceThreshold: Double = 10,
        resetWindow: TimeInterval = resetWindow,
        includeReset: Bool = true
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []

        if let balance = snapshot.balance,
           balance.isAvailable,
           balance.total <= lowBalanceThreshold {
            let money = TideFormatter.money(balance.total, currency: balance.currency, style: .hero)
            events.append(
                AlertEvent(
                    key: "balance-\(account.id.uuidString)",
                    title: T("\(account.name) 余额偏低", "\(account.name) balance is low"),
                    body: T(
                        "当前可用 \(money)，记得及时充值。",
                        "Available balance is \(money). Consider topping up."
                    )
                )
            )
        }

        for quota in snapshot.quotas {
            let cycle = quota.resetDate.map { String(Int($0.timeIntervalSince1970)) } ?? "static"
            let percent = TideFormatter.percent(quota.remainingPercent)

            if quota.remainingPercent <= 10 {
                let resetNote: String
                if let reset = quota.resetDate {
                    resetNote = T(
                        "，\(TideFormatter.countdown(to: reset))",
                        ", resets in \(TideFormatter.countdownShort(to: reset))"
                    )
                } else {
                    resetNote = ""
                }
                events.append(
                    AlertEvent(
                        key: "quota-\(account.id.uuidString)-\(quota.kind.rawValue)-\(cycle)",
                        title: T("\(account.name) 额度不足", "\(account.name) quota is low"),
                        body: T(
                            "\(quota.kind.displayName)额度剩余 \(percent)\(resetNote)。",
                            "\(quota.kind.displayName) quota has \(percent) left\(resetNote)."
                        )
                    )
                )
            }

            if includeReset,
               let reset = quota.resetDate,
               reset > now,
               reset.timeIntervalSince(now) <= resetWindow {
                let countdown = TideFormatter.countdownShort(to: reset, now: now)
                events.append(
                    AlertEvent(
                        key: "reset-\(account.id.uuidString)-\(quota.kind.rawValue)-\(cycle)",
                        title: T("\(account.name) 额度即将重置", "\(account.name) quota resets soon"),
                        body: T(
                            "\(quota.kind.displayName)额度将在 \(countdown) 后重置，当前剩余 \(percent)。",
                            "\(quota.kind.displayName) quota resets in \(countdown), \(percent) left."
                        )
                    )
                )
            }
        }

        return events
    }
}
