// swift-tools-version:6.0
import Foundation
import PackageDescription

// Command Line Tools 只带 Swift Testing 的宏插件，不带 XCTest；
// 这里显式加载 TestingMacros，让 `swift test` 在纯 CLT 环境也能跑。
// 装了完整 Xcode 时不能加这个 flag（避免把 CLT 的插件塞给 Xcode 工具链）。
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let hasXcode = ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? [])
    .contains { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
let needsCLTWorkaround = !hasXcode && FileManager.default.fileExists(atPath: cltTestingPlugin)
let testSwiftSettings: [SwiftSetting] = needsCLTWorkaround
    ? [.unsafeFlags([
        "-Xfrontend", "-load-resolved-plugin",
        "-Xfrontend", "\(cltTestingPlugin)##TestingMacros"
    ])]
    : []

let package = Package(
    name: "Tidepool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tidepool", targets: ["Tidepool"])
    ],
    targets: [
        .executableTarget(
            name: "Tidepool",
            path: "Sources/Tidepool",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TidepoolTests",
            dependencies: ["Tidepool"],
            path: "Tests/TidepoolTests",
            swiftSettings: testSwiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)
