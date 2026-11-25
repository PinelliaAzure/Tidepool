import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用：不占用 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        AppStore.shared.bootstrap()
        UsageStore.shared.start()

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-menu-bar") {
            AppStore.shared.seedPreviewData()
            UsageStore.shared.seedPreviewData()
            Prefs.onboardingDone = true
        }
#endif

        let controller = StatusItemController(store: AppStore.shared)
        statusController = controller

        if AppStore.shared.accounts.isEmpty && !Prefs.onboardingDone {
            OnboardingWindowController.shared.show()
        }
    }
}
