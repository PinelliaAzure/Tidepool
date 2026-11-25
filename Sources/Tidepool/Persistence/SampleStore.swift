import Foundation

/// 余额水位采样：相邻 15 分钟内且变化小于一分钱的刷新不重复记录，
/// 滚动保留最近 30 天。
final class SampleStore {
    private var data: [UUID: [SamplePoint]] = [:]
    private let persistence: PersistenceController?
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        self.persistence = persistent ? PersistenceController() : nil
    }

    func load() {
        guard persistent else { return }
        data = persistence?.loadSamples() ?? [:]
    }

    func samples(for id: UUID) -> [SamplePoint] {
        data[id] ?? []
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
}
