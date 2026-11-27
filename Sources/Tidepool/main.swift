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
        let variants: [(String, ProviderID?)] = [
            ("tidepool-app-mark.png", nil),
            ("tidepool-deepseek-color.png", .deepseek),
            ("tidepool-deepseek-mono.png", .deepseek),
            ("tidepool-kimi.png", .moonshot),
            ("tidepool-kimicode-color.png", .kimiCode),
            ("tidepool-kimicode-mono.png", .kimiCode),
            ("tidepool-glm.png", .glm),
            ("tidepool-openrouter.png", .openrouter),
            ("tidepool-siliconflow.png", .siliconFlow),
            ("tidepool-volcengine-color.png", .volcengine),
            ("tidepool-tencent-color.png", .tencent),
            ("tidepool-huawei-color.png", .huawei),
            ("tidepool-alibaba-color.png", .alibaba),
            ("tidepool-qianfan-color.png", .qianfan)
        ]
        for (name, provider) in variants {
            let image = StatusIconRenderer.menuBarIcon(
                provider: provider,
                colorMode: true,
                dot: provider == .deepseek ? NSColor.systemRed : NSColor.white,
                size: 256
            )
            let url = directory.appendingPathComponent(name)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                print(url.path)
            }
        }

        // 单色模式下的彩色圆点
        let monoVariants: [(String, ProviderID, NSColor)] = [
            ("tidepool-deepseek-mono-red.png", .deepseek, .systemRed),
            ("tidepool-deepseek-mono-green.png", .deepseek, .systemGreen),
            ("tidepool-volcengine-mono-white.png", .volcengine, .white)
        ]
        for (name, provider, dot) in monoVariants {
            let image = StatusIconRenderer.menuBarIcon(
                provider: provider,
                colorMode: false,
                dot: dot,
                size: 256
            )
            let url = directory.appendingPathComponent(name)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                print(url.path)
            }
        }

        // 「全部」模式合成图（logo + 数值 + 状态圆点）
        func sample(_ string: String) -> NSAttributedString {
            NSAttributedString(
                string: string,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.black
                ]
            )
        }
        let allItems: [AppStore.MenuBarItem] = [
            AppStore.MenuBarItem(provider: .deepseek, value: sample("¥42.50"), dotColor: .systemRed),
            AppStore.MenuBarItem(provider: .moonshot, value: sample("¥156.8"), dotColor: .white),
            AppStore.MenuBarItem(provider: .glm, value: sample("72%"), dotColor: .white),
            AppStore.MenuBarItem(provider: .qianfan, value: sample("88.80"), dotColor: .systemGreen),
            AppStore.MenuBarItem(provider: .volcengine, value: sample("¥1.2k"), dotColor: .white),
            AppStore.MenuBarItem(provider: .custom, value: sample("57%"), dotColor: .white)
        ]
        for (name, colorMode) in [("tidepool-all-mode-color.png", true), ("tidepool-all-mode-mono.png", false)] {
            let composite = StatusIconRenderer.allProvidersIcon(items: allItems, colorMode: colorMode, height: 44)
            // 垫一层浅灰底，方便目检深浅色文字
            let wrapped = NSImage(size: NSSize(width: composite.size.width + 16, height: 52))
            wrapped.lockFocus()
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            NSRect(origin: .zero, size: wrapped.size).fill()
            composite.draw(in: NSRect(x: 8, y: 4, width: composite.size.width, height: composite.size.height))
            wrapped.unlockFocus()
            let url = directory.appendingPathComponent(name)
            if let tiff = wrapped.tiffRepresentation,
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
if ProcessInfo.processInfo.arguments.contains("--safari-cookie-test") {
    MainActor.assumeIsolated {
        do {
            let header = try SafariCookieReader.cookieHeader(for: "cloud.siliconflow.cn")
            print("cookies: \(header.count) chars, auth=\(header.contains("__SF_auth.session-token"))")
        } catch {
            print("error: \(error.localizedDescription)")
        }
        exit(0)
    }
}
#endif

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--siliconflow-login") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        SiliconFlowLoginWindowController.shared.show { _ in }
        app.run()
    }
}
#endif

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("--dot-check") {
    MainActor.assumeIsolated {
        print("menuBarStyle:", Prefs.menuBarStyle.rawValue)
        print("colorLogo:", Prefs.colorLogo)
        print("showPricing:", Prefs.showPricing)
        if let status = ProviderPricing.status(for: .deepseek) {
            print("deepseek offPeak:", status.isOffPeak, "label:", status.currentLabel)
        } else {
            print("deepseek pricing: nil")
        }
        print("now:", Date())
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
