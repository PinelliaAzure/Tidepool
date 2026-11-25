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

        let panelSize = NSSize(width: 388, height: 620)
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: AnyView(PopoverRootView().environment(store)))
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
