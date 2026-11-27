// swift-tools-version:6.0
import Foundation
import PackageDescription

// Command Line Tools 只带 Swift Testing 的宏插件，不带 XCTest；
// 这里显式加载 TestingMacros，让 `swift test` 在纯 CLT 环境也能跑。
// 以 xcode-select 当前指向为准：指向 CLT 时即使装了完整 Xcode 也需要这个 workaround。
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let developerDir: String = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
}()
let usesCLT = developerDir.contains("CommandLineTools")
let needsCLTWorkaround = usesCLT && FileManager.default.fileExists(atPath: cltTestingPlugin)
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
