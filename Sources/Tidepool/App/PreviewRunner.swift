#if DEBUG
import AppKit
import SwiftUI

/// 仅开发期使用：
/// - `swift run Tidepool --preview` 以假数据展示面板（不读写真实账户）
/// - 会把窗口号写入临时文件，方便 `screencapture -l` 截一张干净的效果图
@MainActor
enum PreviewRunner {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let store = AppStore.shared
        store.seedPreviewData()
        UsageStore.shared.seedPreviewData()
        if ProcessInfo.processInfo.arguments.contains("--preview-privacy") {
            store.setPreviewPrivacy(true)
        }

        if ProcessInfo.processInfo.arguments.contains("--preview-onboarding") {
            let args = ProcessInfo.processInfo.arguments
            var step = OnboardingView.Step.welcome
            if let index = args.firstIndex(of: "--onboarding-step"),
               index + 1 < args.count,
               let raw = Int(args[index + 1]),
               let parsed = OnboardingView.Step(rawValue: raw) {
                step = parsed
            }
            let size = NSSize(width: 540, height: 600)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: OnboardingView(initialStep: step)
                    .environment(store)
            )
            window.setContentSize(size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)

            let idPath = NSTemporaryDirectory() + "tidepool-preview-window-id"
            try? "\(window.windowNumber)".write(toFile: idPath, atomically: true, encoding: .utf8)
            app.run()
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
            let size = NSSize(width: 660, height: 660)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView().environment(store)
            )
            window.setContentSize(size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            app.activate(ignoringOtherApps: true)

            let idPath = NSTemporaryDirectory() + "tidepool-preview-window-id"
            try? "\(window.windowNumber)".write(toFile: idPath, atomically: true, encoding: .utf8)
            app.run()
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--preview-usage") {
            let size = NSSize(width: 780, height: 660)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = T("Tidepool · 本地用量", "Tidepool · Local usage")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: UsageWindowView()
                    .environment(store)
                    .environment(UsageStore.shared)
            )
            window.setContentSize(size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)

            let idPath = NSTemporaryDirectory() + "tidepool-preview-window-id"
            try? "\(window.windowNumber)".write(toFile: idPath, atomically: true, encoding: .utf8)
            app.run()
            return
        }

        let panelSize = NSSize(width: 388, height: 700)
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(
            rootView: AnyView(
                PopoverRootView()
                    .environment(store)
                    .environment(UsageStore.shared)
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.contentView = effect
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 420, y: frame.maxY - 12))
        }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let idPath = NSTemporaryDirectory() + "tidepool-preview-window-id"
        try? "\(window.windowNumber)".write(toFile: idPath, atomically: true, encoding: .utf8)
        app.run()
    }
}
#endif
