import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用：不占用 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 从 DMG 直接运行后推出磁盘会让映射的二进制失效并 SIGBUS，直接拦下来。
        if Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            InstallWarningWindowController.shared.show()
            return
        }

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

#if DEBUG
        // 调试：绕过鼠标事件直接打开面板，验证 Popover 渲染。
        if ProcessInfo.processInfo.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                controller.simulateStatusItemClick()
            }
        }
#endif
    }
}
