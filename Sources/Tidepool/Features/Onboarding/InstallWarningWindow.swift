import AppKit
import SwiftUI

/// 从 DMG 直接运行时的安装引导窗口。
/// 直接运行磁盘映像里的 App，在推出映像后会让二进制页失效并崩溃，所以这里先拦截。
@MainActor
final class InstallWarningWindowController {
    static let shared = InstallWarningWindowController()
    private var window: NSWindow?

    func show() {
        let size = NSSize(width: 480, height: 260)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = T("安装 Tidepool", "Install Tidepool")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: InstallWarningView(
                onInstall: { self.installAndRelaunch() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        window.setContentSize(size)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
            }

    private func installAndRelaunch() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications/Tidepool.app")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = [source.path, destination.path]
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                throw NSError(domain: "Tidepool", code: 1)
            }
            NSWorkspace.shared.open(destination)
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = T("安装失败", "Installation failed")
            alert.informativeText = T(
                "请手动把 Tidepool 拖进 Applications 文件夹后再打开。",
                "Drag Tidepool into Applications manually, then open it."
            )
            alert.addButton(withTitle: T("好", "OK"))
            alert.runModal()
        }
    }
}

private struct InstallWarningView: View {
    var onInstall: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: ProviderIconRenderer.appMark(size: 48, tint: NSColor(hex: 0x4D6BFE)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("先把 Tidepool 安装到「应用程序」", "Install Tidepool first"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(T("不要直接从磁盘映像运行", "Don't run it straight from the disk image"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(T(
                "从 DMG 直接运行，推出磁盘映像后 Tidepool 会崩溃（SIGBUS）。点下面的按钮会自动复制到 Applications 并打开。",
                "Running from the DMG crashes Tidepool (SIGBUS) after the image is ejected. The button below copies it to Applications and opens it."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(T("退出", "Quit"), action: onQuit)
                    .controlSize(.large)
                Button(T("安装并打开", "Install & open"), action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
