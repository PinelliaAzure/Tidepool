import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用：不占用 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        AppStore.shared.bootstrap()
        let controller = StatusItemController(store: AppStore.shared)
        statusController = controller
    }
}
