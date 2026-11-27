import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用：不占用 Dock 图标
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

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

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.flushPendingWrites()
    }

    /// 菜单栏应用（LSUIElement）没有默认主菜单，⌘C / ⌘V / ⌘A 挂在「编辑」菜单上：
    /// 不建主菜单，文本框里 Cmd+V 无处派发，只能靠双击右键粘贴。
    /// 主菜单虽然不可见（accessory），但菜单项的快捷键在窗口成为 key 时依然生效。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: T("退出 Tidepool", "Quit Tidepool"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let edit = NSMenu(title: T("编辑", "Edit"))
        edit.addItem(withTitle: T("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: T("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: T("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: T("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: T("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: T("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = edit
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
