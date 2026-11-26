import AppKit
import SwiftUI

/// 首次启动引导窗口。
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var suppressAutoShow = false

    func show(force: Bool = false) {
        guard force || !Prefs.onboardingDone else { return }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = T("欢迎使用 Tidepool", "Welcome to Tidepool")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    onFinish: { [weak self] in self?.close() },
                    onSkip: { [weak self] in self?.close() }
                )
                .environment(AppStore.shared)
            )
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // 只有完成 / 跳过引导才标记 done；直接关窗不算完成，下次启动会再次出现
        window = nil
    }
}
