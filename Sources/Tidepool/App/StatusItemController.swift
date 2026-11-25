import AppKit
import SwiftUI

/// 菜单栏外壳：负责状态图标、左右键行为与 Popover 的展示。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: AppStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var contextMenu: NSMenu?
    private var popoverController: NSHostingController<AnyView>?

    init(store: AppStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        store.onMenuChanged = { [weak self] in self?.refreshStatusItem() }
        store.onOpenSettings = { [weak self] in self?.showSettings() }
        store.onOpenUsage = { UsageWindowController.shared.show() }

        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.action = #selector(handleButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        refreshStatusItem()
    }

    /// 依据 AppStore 的最新状态刷新菜单栏显示。
    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let content = store.menuBarContent
        let tint: NSColor? = store.colorLogo
            ? (content.accent ?? ProviderID.deepseek.nsBrandColor)
            : nil
        button.image = StatusIconRenderer.menuBarIcon(
            tint: tint,
            alert: content.alert,
            offPeak: content.offPeak
        )
        button.title = content.text ?? ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshAll(_:)), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let usage = NSMenuItem(title: "本地用量…", action: #selector(openUsage(_:)), keyEquivalent: "u")
        usage.target = self
        menu.addItem(usage)

        let privacy = NSMenuItem(title: "隐私模式", action: #selector(togglePrivacy(_:)), keyEquivalent: "p")
        privacy.target = self
        privacy.state = store.privacyMode ? .on : .off
        menu.addItem(privacy)

        let updates = NSMenuItem(title: "检查更新…", action: #selector(checkUpdates(_:)), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: "Tidepool 设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Tidepool", action: #selector(quit(_:)), keyEquivalent: "q")
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
        UpdateChecker.openReleases()
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
