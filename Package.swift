// swift-tools-version:6.0
import Foundation
import PackageDescription

// Command Line Tools 只带 Swift Testing 的宏插件，不带 XCTest；
// 这里显式加载 TestingMacros，让 `swift test` 在纯 CLT 环境也能跑。
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingPlugin)
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
