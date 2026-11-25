import AppKit
import Foundation

/// 轻量更新入口：打开 GitHub Releases（不引入 Sparkle / 网络轮询）。
/// 发布仓库变更时只需改这里。
enum UpdateChecker {
    static let repositoryURL = URL(string: "https://github.com/PinelliaAzure/Tidepool")!

    static var releasesURL: URL {
        repositoryURL.appendingPathComponent("releases")
    }

    @MainActor
    static func openReleases() {
        NSWorkspace.shared.open(releasesURL)
    }
}
