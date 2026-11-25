import AppKit
import Foundation

/// 轮询调度：按账户间隔刷新；失败指数退避（上限 30 分钟）；
/// 睡眠暂停、唤醒立即补刷。
@MainActor
final class RefreshScheduler {
    private weak var store: AppStore?
    private var timer: Timer?
    private var nextRun: [UUID: Date] = [:]
    private var failures: [UUID: Int] = [:]
    private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func attach(_ store: AppStore) {
        self.store = store
        startTimer()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshDue(force: true)
                }
            }
        )
        refreshDue(force: true)
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDue()
            }
        }
    }

    private func refreshDue(force: Bool = false) {
        guard let store else { return }
        for account in store.accounts where account.enabled {
            let isDue = nextRun[account.id].map { $0 <= Date() } ?? true
            guard force || isDue else { continue }
            let id = account.id
            Task { [weak self] in
                let ok = await store.refresh(id, force: force)
                self?.recordResult(account: account, success: ok)
            }
        }
    }

    private func recordResult(account: ProviderAccount, success: Bool) {
        if success {
            failures[account.id] = 0
            nextRun[account.id] = Date().addingTimeInterval(TimeInterval(account.intervalSeconds))
        } else {
            let count = (failures[account.id] ?? 0) + 1
            failures[account.id] = count
            let base = TimeInterval(max(account.intervalSeconds, 60))
            let delay = min(base * pow(2, Double(min(count, 5))), 1_800)
            nextRun[account.id] = Date().addingTimeInterval(delay)
        }
    }
}
