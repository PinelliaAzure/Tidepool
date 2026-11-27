import AppKit
import Foundation

/// 应用内更新：读取 GitHub Releases 最新版本 → 下载 zip → 替换当前 App → 重启。
/// 只在用户点击「检查更新」时联网，不做后台轮询。
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private struct RemoteRelease {
        var version: String
        var zipURL: URL?
        var htmlURL: URL
    }

    private enum UpdateError: LocalizedError {
        case network
        case noZip
        case invalidPackage
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .network:
                return T("无法连接 GitHub，请检查网络后重试。", "Could not reach GitHub. Check your network and try again.")
            case .noZip:
                return T("最新版本没有提供 zip 安装包。", "The latest release has no zip package.")
            case .invalidPackage:
                return T("更新包无效或版本不匹配。", "The update package is invalid or does not match.")
            case .installFailed(let message):
                return message
            }
        }
    }

    private var isChecking = false
    private var progressPanel: NSPanel?

    private init() {}

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - 入口

    func checkForUpdates() {
        guard !isChecking else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            showInfo(
                T("开发模式", "Development mode"),
                T("应用内更新仅支持打包后的 Tidepool.app。", "In-app updates only work in the packaged Tidepool.app.")
            )
            return
        }
        isChecking = true
        Task { [weak self] in
            defer { self?.isChecking = false }
            guard let self else { return }
            do {
                guard let release = try await Self.fetchLatestRelease() else {
                    self.showError(
                        T("检查更新失败", "Update check failed"),
                        T("无法读取最新发布信息，请稍后再试。", "Could not read the latest release. Try again later.")
                    )
                    return
                }
                guard Self.isNewer(release.version, than: self.currentVersion) else {
                    self.showInfo(
                        T("已是最新版本", "You're up to date"),
                        T("当前版本 \(self.currentVersion)。", "Current version \(self.currentVersion).")
                    )
                    return
                }
                self.promptInstall(release)
            } catch {
                self.showError(
                    T("检查更新失败", "Update check failed"),
                    error.localizedDescription
                )
            }
        }
    }

    // MARK: - 提示

    private func promptInstall(_ release: RemoteRelease) {
        NSApp.activate(ignoringOtherApps: true)
        guard let zipURL = release.zipURL else {
            let alert = NSAlert()
            alert.messageText = T("发现新版本 \(release.version)", "Version \(release.version) is available")
            alert.informativeText = T(
                "最新版本没有提供自动更新包，请到 Release 页面手动下载。",
                "The latest release has no auto-update package. Download it from the release page."
            )
            alert.addButton(withTitle: T("打开下载页", "Open downloads"))
            alert.addButton(withTitle: T("取消", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = T("发现新版本 \(release.version)", "Version \(release.version) is available")
        alert.informativeText = T(
            "当前版本 \(currentVersion)。是否立即下载并安装？App 会自动重启。",
            "Current version \(currentVersion). Download and install now? The app will relaunch automatically."
        )
        alert.addButton(withTitle: T("下载并安装", "Download & install"))
        alert.addButton(withTitle: T("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        performUpdate(release, zipURL: zipURL)
    }

    // MARK: - 下载与安装

    private func performUpdate(_ release: RemoteRelease, zipURL: URL) {
        showProgress(T("正在下载更新…", "Downloading update…"))
        Task { [weak self] in
            guard let self else { return }
            do {
                let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.network
                }
                self.updateProgress(T("正在安装…", "Installing…"))
                let appURL = try await Task.detached(priority: .userInitiated) {
                    try Self.install(zip: downloaded)
                }.value
                self.hideProgress()

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", appURL.path]
                try? task.run()
                NSApp.terminate(nil)
            } catch {
                self.hideProgress()
                self.showError(T("更新失败", "Update failed"), error.localizedDescription)
            }
        }
    }

    nonisolated private static func install(zip: URL) throws -> URL {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("TidepoolUpdate-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try run("/usr/bin/ditto", ["-xk", zip.path, workDir.path])
        guard let newApp = try fileManager.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.invalidPackage
        }

        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        let version = NSDictionary(contentsOf: plistURL)?["CFBundleShortVersionString"] as? String ?? ""
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard !version.isEmpty, isNewer(version, than: installed) else {
            throw UpdateError.invalidPackage
        }

        let destination = Bundle.main.bundleURL
        let staging = fileManager.temporaryDirectory.appendingPathComponent("Tidepool-new-\(UUID().uuidString).app")
        try? fileManager.removeItem(at: staging)
        try fileManager.moveItem(at: newApp, to: staging)

        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            // /Applications 不可写时走管理员授权
            try privilegedReplace(from: staging, to: destination)
        }

        try? fileManager.removeItem(at: workDir)
        return destination
    }

    /// 兜底的提权替换（会弹出系统管理员授权框）。
    nonisolated private static func privilegedReplace(from source: URL, to destination: URL) throws {
        func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let command = "rm -rf \(quote(destination.path)) && ditto \(quote(source.path)) \(quote(destination.path))"
        let script = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.installFailed(
                message.isEmpty
                    ? T("无法替换应用程序，请手动下载安装。", "Could not replace the app. Download and install it manually.")
                    : message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: - 版本与网络

    nonisolated private static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.installFailed(
                message.isEmpty
                    ? T("解压更新包失败。", "Could not unpack the update package.")
                    : message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    nonisolated private static func fetchLatestRelease() async throws -> RemoteRelease? {
        var request = URLRequest(url: UpdateChecker.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
        guard http.statusCode == 200 else { throw UpdateError.network }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let html = root["html_url"] as? String,
              let htmlURL = URL(string: html) else {
            return nil
        }
        let assets = root["assets"] as? [[String: Any]] ?? []
        let zipAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let zipURL = (zipAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return RemoteRelease(version: version, zipURL: zipURL, htmlURL: htmlURL)
    }

    // MARK: - 简单 UI

    private func showInfo(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: T("好", "OK"))
        alert.runModal()
    }

    private func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: T("好", "OK"))
        alert.runModal()
    }

    private func showProgress(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 92),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = T("Tidepool 更新", "Tidepool Update")
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel

        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 60, y: 50, width: 244, height: 20)
        let spinner = NSProgressIndicator(frame: NSRect(x: 22, y: 46, width: 24, height: 24))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(spinner)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressPanel = panel
    }

    private func updateProgress(_ text: String) {
        progressPanel?.contentView?.subviews
            .compactMap { $0 as? NSTextField }
            .first?
            .stringValue = text
    }

    private func hideProgress() {
        progressPanel?.close()
        progressPanel = nil
    }
}
