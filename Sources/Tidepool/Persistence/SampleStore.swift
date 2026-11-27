import Foundation

/// 余额与额度采样：相邻 15 分钟内且变化很小的刷新不重复记录，
/// 滚动保留最近 30 天。
final class SampleStore {
    private var data: [UUID: [SamplePoint]] = [:]
    private var quotaData: [UUID: [QuotaSamplePoint]] = [:]
    private let persistence: PersistenceController?
    private let persistent: Bool
    /// 合并短时间内的多次写入，避免每次刷新都全量重写 JSON。
    private var pendingSave: DispatchWorkItem?

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
        scheduleSave()
    }

    func appendQuota(accountID: UUID, kind: QuotaKind, percent: Double, now: Date) {
        var list = quotaData[accountID] ?? []
        if let last = list.last(where: { $0.kind == kind }),
           now.timeIntervalSince(last.date) < 900,
           abs(last.remainingPercent - percent) < 0.5 {
            return
        }
        list.append(QuotaSamplePoint(date: now, kind: kind, remainingPercent: percent))
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        list.removeAll { $0.date < cutoff }
        quotaData[accountID] = list
        scheduleSave()
    }

    /// 删除某个账户的全部采样（账户被移除时调用），并立即落盘。
    func purge(accountID: UUID) {
        guard data[accountID] != nil || quotaData[accountID] != nil else { return }
        data[accountID] = nil
        quotaData[accountID] = nil
        flush()
    }

    /// 立即把待写入的采样落盘（退出应用前调用）。
    func flush() {
        guard persistent, let persistence else { return }
        pendingSave?.cancel()
        pendingSave = nil
        persistence.saveSamples(data)
        persistence.saveQuotaSamples(quotaData)
    }

    private func scheduleSave() {
        guard persistent, let persistence else { return }
        pendingSave?.cancel()
        let sampleSnapshot = data
        let quotaSnapshot = quotaData
        let work = DispatchWorkItem {
            persistence.saveSamples(sampleSnapshot)
            persistence.saveQuotaSamples(quotaSnapshot)
        }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }
}
