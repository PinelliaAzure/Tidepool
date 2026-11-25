import AppKit
import SwiftUI

/// 独立的设置窗口（AppKit 窗口承载 SwiftUI 内容）。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Tidepool 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environment(AppStore.shared))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }
}
