import AppKit

// Tidepool —— macOS 菜单栏的大模型余额与余量仪表盘。
// AppKit 外壳 + SwiftUI 内容：NSStatusItem 常驻菜单栏，NSPopover 展示面板。

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--usage-report") {
    MainActor.assumeIsolated {
        let since = Date().addingTimeInterval(-30 * 86_400)
        let records = OpenCodeUsageScanner().scan(since: since)
        let summary = UsageSummary(records: records, now: Date())
        print("records: \(records.count)")
        print("tokens30: \(summary.totalTokens(days: 30)) cost30: \(String(format: "%.4f", summary.totalCost(days: 30)))")
        for model in summary.models(days: 30).prefix(8) {
            print("  \(model.provider)/\(model.model) tokens=\(model.tokens) cost=\(String(format: "%.4f", model.cost)) req=\(model.requests)")
        }
        for tool in summary.tools(days: 30) {
            print("  tool=\(tool.tool) tokens=\(tool.tokens) req=\(tool.requests)")
        }
        exit(0)
    }
}
#endif

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--dump-icon") {
    MainActor.assumeIsolated {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let variants: [(String, Bool, Bool)] = [
            ("tidepool-whale.png", false, false),
            ("tidepool-whale-offpeak.png", true, false),
            ("tidepool-whale-alert.png", false, true)
        ]
        for (name, offPeak, alert) in variants {
            let image = StatusIconRenderer.menuBarIcon(
                size: 256,
                tint: .black,
                alert: alert,
                offPeak: offPeak
            )
            let url = directory.appendingPathComponent(name)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                print(url.path)
            }
        }
        exit(0)
    }
}
#endif

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--preview")
    || ProcessInfo.processInfo.arguments.contains("--preview-quota")
    || ProcessInfo.processInfo.arguments.contains("--preview-usage")
    || ProcessInfo.processInfo.arguments.contains("--preview-onboarding")
    || ProcessInfo.processInfo.arguments.contains("--preview-settings") {    MainActor.assumeIsolated {
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
