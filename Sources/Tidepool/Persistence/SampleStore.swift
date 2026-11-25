import Foundation

/// 余额与额度采样：相邻 15 分钟内且变化很小的刷新不重复记录，
/// 滚动保留最近 30 天。
final class SampleStore {
    private var data: [UUID: [SamplePoint]] = [:]
    private var quotaData: [UUID: [QuotaSamplePoint]] = [:]
    private let persistence: PersistenceController?
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        self.persistence = persistent ? PersistenceController() : nil
    }

    func load() {
        guard persistent else { return }
        data = persistence?.loadSamples() ?? [:]
        quotaData = persistence?.loadQuotaSamples() ?? [:]
    }

    func samples(for id: UUID) -> [SamplePoint] {
        data[id] ?? []
    }

    func quotaSamples(for id: UUID, kind: QuotaKind) -> [QuotaSamplePoint] {
        (quotaData[id] ?? []).filter { $0.kind == kind }
    }

    func append(accountID: UUID, value: Double, now: Date) {
        var list = data[accountID] ?? []
        if let last = list.last,
           now.timeIntervalSince(last.date) < 900,
           abs(last.value - value) < 0.01 {
            return
        }
        list.append(SamplePoint(date: now, value: value))
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        list.removeAll { $0.date < cutoff }
        data[accountID] = list
        if persistent {
            persistence?.saveSamples(data)
        }
    }

    func appendQuota(accountID: UUID, kind: QuotaKind, percent: Double, now: Date) {
        var list = quotaData[accountID] ?? []
        // 同一额度窗口内，15 分钟内且变化小于 0.5% 的采样忽略
        if let last = list.last(where: { $0.kind == kind }),
           now.timeIntervalSince(last.date) < 900,
           abs(last.remainingPercent - percent) < 0.5 {
            return
        }
        list.append(QuotaSamplePoint(date: now, kind: kind, remainingPercent: percent))
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        list.removeAll { $0.date < cutoff }
        quotaData[accountID] = list
        if persistent {
            persistence?.saveQuotaSamples(quotaData)
        }
    }
}
