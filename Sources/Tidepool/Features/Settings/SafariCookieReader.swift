import Foundation

/// 从 Safari 的 Cookies.binarycookies 读取指定站点的 Cookie。
/// 注意：Safari 的容器目录受 macOS「完全磁盘访问权限」保护，未授权时会抛 permissionDenied。
enum SafariCookieReader {
    struct Cookie {
        let domain: String
        let name: String
        let path: String
        let value: String
        let expiresAt: Date?
    }

    enum ReadError: LocalizedError {
        case notFound
        case permissionDenied
        case noSession
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .notFound:
                return T(
                    "没有找到 Safari 的 Cookie 文件。请先在 Safari 里登录 cloud.siliconflow.cn。",
                    "Safari cookies were not found. Sign in to cloud.siliconflow.cn in Safari first."
                )
            case .permissionDenied:
                return T(
                    "Safari 的 Cookie 受 macOS 保护。请到「系统设置 → 隐私与安全性 → 完全磁盘访问权限」勾选 Tidepool 后重试，或改用「在 Tidepool 中登录」。",
                    "Safari cookies are protected by macOS. Allow Tidepool in System Settings → Privacy & Security → Full Disk Access, or use “Sign in with Tidepool”."
                )
            case .noSession:
                return T(
                    "Safari 里没有找到硅基流动的登录 Cookie。请先在 Safari 登录 cloud.siliconflow.cn。",
                    "No SiliconFlow session cookie in Safari. Sign in to cloud.siliconflow.cn in Safari first."
                )
            case .parseFailed:
                return T(
                    "无法解析 Safari 的 Cookie 文件，可能格式已变化。",
                    "Could not parse Safari's cookie file; its format may have changed."
                )
            }
        }
    }

    static func cookieHeader(for host: String) throws -> String {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        ]

        var sawFile = false
        var sawPermissionError = false

        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            sawFile = true
            do {
                let data = try Data(contentsOf: path)
                let cookies = try parse(data)
                let header = header(from: cookies, for: host)
                if !header.isEmpty { return header }
            } catch let error as ReadError {
                throw error
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
                    sawPermissionError = true
                    continue
                }
                if nsError.domain == NSPOSIXErrorDomain && nsError.code == 1 {
                    sawPermissionError = true
                    continue
                }
                throw ReadError.parseFailed
            }
        }

        if sawPermissionError { throw ReadError.permissionDenied }
        if !sawFile { throw ReadError.notFound }
        throw ReadError.noSession
    }

    static func header(from cookies: [Cookie], for host: String) -> String {
        let now = Date()
        var selected: [String: Cookie] = [:]

        for cookie in cookies {
            guard matches(host: host, domain: cookie.domain) else { continue }
            if let expiry = cookie.expiresAt, expiry < now { continue }
            if let existing = selected[cookie.name] {
                // 同名的 Cookie 优先保留路径更具体的那个
                if existing.path.count > cookie.path.count { continue }
            }
            selected[cookie.name] = cookie
        }

        return selected.values
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private static func matches(host: String, domain: String) -> Bool {
        let normalized = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard !normalized.isEmpty else { return false }
        return host == normalized || host.hasSuffix("." + normalized)
    }

    // MARK: - binarycookies 解析

    static func parse(_ data: Data) throws -> [Cookie] {
        let bytes = [UInt8](data)
        // 文件头是 7 字节 "cookies"，随后才是页数和每页大小。
        guard bytes.count >= 11,
              bytes[0] == 0x63, bytes[1] == 0x6F, bytes[2] == 0x6F, bytes[3] == 0x6B,
              bytes[4] == 0x69, bytes[5] == 0x65, bytes[6] == 0x73 else {
            throw ReadError.parseFailed
        }

        let pageCount = Int(readUInt32BE(bytes, 7))
        guard pageCount > 0, pageCount < 10_000 else { throw ReadError.parseFailed }

        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(pageCount)
        var cursor = 11
        for _ in 0..<pageCount {
            guard cursor + 4 <= bytes.count else { throw ReadError.parseFailed }
            pageSizes.append(Int(readUInt32BE(bytes, cursor)))
            cursor += 4
        }

        var cookies: [Cookie] = []
        for pageSize in pageSizes {
            guard pageSize >= 8, cursor + pageSize <= bytes.count else { throw ReadError.parseFailed }
            let pageStart = cursor
            let pageEnd = cursor + pageSize
            cursor = pageEnd

            guard bytes[pageStart] == 0, bytes[pageStart + 1] == 0,
                  bytes[pageStart + 2] == 1, bytes[pageStart + 3] == 0 else {
                throw ReadError.parseFailed
            }

            let cookieCount = Int(readUInt32LE(bytes, pageStart + 4))
            guard cookieCount >= 0, cookieCount < 100_000 else { throw ReadError.parseFailed }
            let offsetsStart = pageStart + 8
            guard offsetsStart + cookieCount * 4 <= pageEnd else { throw ReadError.parseFailed }

            for index in 0..<cookieCount {
                let cookieOffset = Int(readUInt32LE(bytes, offsetsStart + index * 4))
                let start = pageStart + cookieOffset
                guard start + 48 <= pageEnd else { continue }

                let urlOffset = Int(readUInt32LE(bytes, start + 12))
                let nameOffset = Int(readUInt32LE(bytes, start + 16))
                let pathOffset = Int(readUInt32LE(bytes, start + 20))
                let valueOffset = Int(readUInt32LE(bytes, start + 24))
                let expiry = readDoubleLE(bytes, start + 32)

                func string(at offset: Int) -> String {
                    var index = start + offset
                    guard index >= start, index < pageEnd else { return "" }
                    let begin = index
                    while index < pageEnd, bytes[index] != 0 { index += 1 }
                    return String(decoding: bytes[begin..<index], as: UTF8.self)
                }

                let domain = string(at: urlOffset)
                let name = string(at: nameOffset)
                guard !name.isEmpty else { continue }

                cookies.append(
                    Cookie(
                        domain: domain,
                        name: name,
                        path: string(at: pathOffset),
                        value: string(at: valueOffset),
                        expiresAt: expiry == 0 ? nil : Date(timeIntervalSinceReferenceDate: expiry)
                    )
                )
            }
        }

        return cookies
    }

    private static func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readDoubleLE(_ bytes: [UInt8], _ offset: Int) -> Double {
        guard offset + 8 <= bytes.count else { return 0 }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << (8 * UInt64(index))
        }
        return Double(bitPattern: value)
    }
}
