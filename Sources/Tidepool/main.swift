import AppKit

// Tidepool —— macOS 菜单栏的大模型余额与余量仪表盘。
// AppKit 外壳 + SwiftUI 内容：NSStatusItem 常驻菜单栏，NSPopover 展示面板。

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--dump-icon") {
    MainActor.assumeIsolated {
        let image = StatusIconRenderer.whaleIcon(size: 512, tint: .black)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tidepool-whale.png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print(url.path)
        }
        exit(0)
    }
}
#endif

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--preview") {
    MainActor.assumeIsolated {
        PreviewRunner.run()
        exit(0)
    }
}
#endif

MainActor.assumeIsolated {
    // delegate 是 weak 引用，保持在 run() 期间存活
    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
    NSApplication.shared.run()
}
