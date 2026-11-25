import Foundation

/// 额度节奏：把「时间过去了多少」和「额度用了多少」放在一起比较，
/// 比单纯显示百分比更能回答「现在需不需要克制一点」。
enum QuotaPace {
    struct Status: Equatable {
        var text: String
        var detail: String
        var isFast: Bool
    }

    static func status(quota: QuotaWindow, now: Date = Date()) -> Status? {
        guard let reset = quota.resetDate, let window = quota.kind.windowLength else { return nil }
        let remainingSeconds = reset.timeIntervalSince(now)
        guard remainingSeconds > 0 else { return nil }

        let elapsedFraction = min(max(1 - remainingSeconds / window, 0), 1)
        let usedFraction = 1 - quota.remainingFraction
        let delta = usedFraction - elapsedFraction

        let detail = "时间过去 \(TideFormatter.percent(elapsedFraction * 100)) · 已用 \(TideFormatter.percent(usedFraction * 100))"

        if delta > 0.08 {
            return Status(text: "节奏偏快，按当前速度会提前用完", detail: detail, isFast: true)
        }
        if delta < -0.08 {
            return Status(text: "节奏从容，略慢于时间进度", detail: detail, isFast: false)
        }
        return Status(text: "节奏正常，与时间进度一致", detail: detail, isFast: false)
    }
}
