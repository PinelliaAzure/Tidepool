import Foundation
import Testing
@testable import Tidepool

@Suite("硅基流动控制台")
struct SiliconFlowConsoleTests {
    @Test func sessionRoundTrip() throws {
        let session = SiliconFlowSession(
            cookie: "__SF_auth.session-token=abc; other=1",
            subjectID: "subject-1",
            source: "Safari",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            userAgent: "Test UA"
        )
        let encoded = try #require(session.encoded())
        let decoded = try #require(SiliconFlowSession.decode(encoded))
        #expect(decoded.cookie == session.cookie)
        #expect(decoded.subjectID == session.subjectID)
        #expect(decoded.source == session.source)
        #expect(decoded.userAgent == session.userAgent)
        #expect(abs(decoded.savedAt.timeIntervalSince1970 - 1_700_000_000) < 0.001)
    }

    @Test func parseUserInfo() throws {
        let json = """
        {
          "code": 20000,
          "status": true,
          "data": {
            "balance": "1.20",
            "chargeBalance": "20.00",
            "totalBalance": "12.34",
            "status": "normal"
          }
        }
        """
        let snapshot = try SiliconFlowConsoleClient.parseUserInfo(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 12.34) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 20) < 0.001)
    }

    @Test func parseWallet() throws {
        // 控制台钱包金额单位是 10^-12 CNY
        let json = """
        {
          "code": 20000,
          "data": {
            "financialInfo": {
              "balance": "12340000000000"
            }
          }
        }
        """
        let snapshot = try SiliconFlowConsoleClient.parseWallet(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 12.34) < 0.001)
    }
}

@Suite("Safari Cookie 读取")
struct SafariCookieReaderTests {
    // 生成好的 binarycookies 测试文件，包含：
    // - .siliconflow.cn  __SF_auth.session-token=abc123（有效）
    // - .example.com     other=nope（其他站点）
    // - .siliconflow.cn  expired=gone（已过期）
    private static let fixtureBase64 = """
    Y29va2llcwAAAAEAAAEOAAABAAMAAAAUAAAAdQAAAL8AAABhAAAAAAAAAAAAAAAwAAAAQAAAAFgAAABaAAAAAAAAAAAAAAAIRstBAAAAQPiCx0Euc2lsaWNvbmZsb3cuY24AX19TRl9hdXRoLnNlc3Npb24tdG9rZW4ALwBhYmMxMjMASgAAAAAAAAAAAAAAMAAAAD0AAABDAAAARQAAAAAAAAAAAAAACEbLQQAAAED4gsdBLmV4YW1wbGUuY29tAG90aGVyAC8Abm9wZQBPAAAAAAAAAAAAAAAwAAAAQAAAAEgAAABKAAAAAAAAAAAAAAAAQI/AAAAAQPiCx0Euc2lsaWNvbmZsb3cuY24AZXhwaXJlZAAvAGdvbmUA
    """

    @Test func parseAndFilter() throws {
        let data = try #require(Data(base64Encoded: Self.fixtureBase64))
        let cookies = try SafariCookieReader.parse(data)
        #expect(cookies.count == 3)

        let header = SafariCookieReader.header(from: cookies, for: "cloud.siliconflow.cn")
        #expect(header.contains("__SF_auth.session-token=abc123"))
        #expect(!header.contains("other=nope"))
        #expect(!header.contains("expired=gone"))
    }
}
