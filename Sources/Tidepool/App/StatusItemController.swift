import AppKit
import SwiftUI

/// 菜单栏外壳：负责状态图标、左右键行为与 Popover 的展示。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let store: AppStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var contextMenu: NSMenu?
    private var popoverController: NSHostingController<AnyView>?
    private var dismissMonitors: [Any] = []
    private var priceTimer: Timer?
    private var appearanceObserver: NSKeyValueObservation?

    init(store: AppStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        store.onMenuChanged = { [weak self] in self?.refreshStatusItem() }
        store.onOpenSettings = { [weak self] in self?.showSettings() }
        store.onOpenUsage = { UsageWindowController.shared.show() }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        refreshStatusItem()

        // 计价时段每 30 秒重算一次，跨过 09:00 / 12:00 / 14:00 / 18:00 时即时切换
        priceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusItem()
            }
        }

        // 外观切换时重绘合成图
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusItem()
            }
        }
    }

    /// 依据 AppStore 的最新状态刷新菜单栏显示。
    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let content = store.menuBarContent

        if !content.allItems.isEmpty {
            // 「全部」模式：品牌 logo + 数值合成一张图，每个 logo 带状态圆点
            button.image = StatusIconRenderer.allProvidersIcon(
                items: content.allItems,
                colorMode: store.colorLogo
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = content.tooltip
            return
        }

        button.image = StatusIconRenderer.menuBarIcon(
            provider: content.provider,
            colorMode: store.colorLogo,
            dot: content.dotColor
        )
        button.attributedTitle = content.title ?? NSAttributedString(string: "")
        button.toolTip = content.tooltip
    }

    // MARK: - 交互

    @objc private func handleButtonClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        switch event.type {
        case .rightMouseUp, .otherMouseUp:
            showContextMenu()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

#if DEBUG
    func simulateStatusItemClick() {
        statusItem.button?.performClick(nil)
    }
#endif

    /// 打开面板（供点击与调试使用）。
    func showPopover() {
        guard let button = statusItem.button else { return }
        if popoverController == nil {
            let controller = NSHostingController(
                rootView: AnyView(
                    PopoverRootView()
                        .environment(store)
                        .environment(UsageStore.shared)
                )
            )
            controller.sizingOptions = [.preferredContentSize]
            popoverController = controller
            popover.contentViewController = controller
        }
        popover.contentSize = NSSize(width: 388, height: 720)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startDismissMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        stopDismissMonitors()
    }

    private func startDismissMonitors() {
        stopDismissMonitors()

        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                guard let self, self.popover.isShown else { return event }
                if let window = event.window,
                   window == self.popover.contentViewController?.view.window {
                    return event
                }
                // 弹出菜单（刷新间隔、Provider 排序）不应触发收起
                if let window = event.window, window.level == .popUpMenu {
                    return event
                }
                if let buttonWindow = self.statusItem.button?.window,
                   event.window == buttonWindow {
                    return event
                }
                self.popover.performClose(nil)
                return event
            }
        ) {
            dismissMonitors.append(local)
        }

        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.popover.isShown else { return }
                    self.popover.performClose(nil)
                }
            }
        ) {
            dismissMonitors.append(global)
        }
    }

    private func stopDismissMonitors() {
        for monitor in dismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dismissMonitors.removeAll()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let refresh = NSMenuItem(title: T("立即刷新", "Refresh now"), action: #selector(refreshAll(_:)), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let usage = NSMenuItem(title: T("本地用量…", "Local usage…"), action: #selector(openUsage(_:)), keyEquivalent: "u")
        usage.target = self
        menu.addItem(usage)

        let privacy = NSMenuItem(title: T("隐私模式", "Privacy mode"), action: #selector(togglePrivacy(_:)), keyEquivalent: "p")
        privacy.target = self
        privacy.state = store.privacyMode ? .on : .off
        menu.addItem(privacy)

        let updates = NSMenuItem(title: T("检查更新…", "Check for updates…"), action: #selector(checkUpdates(_:)), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: T("Tidepool 设置…", "Tidepool Settings…"), action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: T("退出 Tidepool", "Quit Tidepool"), action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        contextMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        contextMenu = nil
    }

    @objc private func refreshAll(_ sender: Any?) {
        Task {
            await store.refreshAll(force: true)
            UsageStore.shared.refresh()
        }
    }

    @objc private func openUsage(_ sender: Any?) {
        UsageWindowController.shared.show()
    }

    @objc private func togglePrivacy(_ sender: Any?) {
        store.togglePrivacy()
    }

    @objc private func checkUpdates(_ sender: Any?) {
        UpdateService.shared.checkForUpdates()
    }

    @objc private func openSettings(_ sender: Any?) {
        showSettings()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        SettingsWindowController.shared.show()
    }
}
