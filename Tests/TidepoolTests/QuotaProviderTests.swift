import Foundation
import Testing
@testable import Tidepool

@Suite("GLM / Kimi Code 额度解析")
struct QuotaProviderTests {
    @Test func glmParsing() throws {
        let json = """
        {
          "code": 200,
          "success": true,
          "msg": "ok",
          "data": {
            "level": "pro",
            "limits": [
              { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 40, "nextResetTime": 1893456000000 },
              { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 25, "nextResetTime": 1894000000000 },
              { "type": "TIME_LIMIT", "unit": 1, "usage": 100, "currentValue": 30, "remaining": 70, "nextResetTime": 1894000000000 }
            ]
          }
        }
        """
        let snapshot = try GLMProvider().parse(Data(json.utf8))

        #expect(snapshot.planName == "GLM Coding Plan · Pro")
        #expect(snapshot.balance == nil)

        let fiveHour = try #require(snapshot.quotas.first { $0.kind == .fiveHour })
        #expect(abs(fiveHour.remainingPercent - 60) < 0.001)
        #expect(fiveHour.resetDate != nil)

        let weekly = try #require(snapshot.quotas.first { $0.kind == .weekly })
        #expect(abs(weekly.remainingPercent - 75) < 0.001)

        let monthly = try #require(snapshot.quotas.first { $0.kind == .monthly })
        #expect(abs(monthly.remainingPercent - 70) < 0.001)

        // 展示顺序：5h → 周 → 月
        #expect(snapshot.sortedQuotas.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(snapshot.tightestQuota?.kind == .fiveHour)
    }

    @Test func glmEmptyLimitsThrows() {
        let json = """
        { "code": 200, "success": true, "data": { "limits": [], "level": "pro" } }
        """
        #expect(throws: (any Error).self) {
            try GLMProvider().parse(Data(json.utf8))
        }
    }

    @Test func kimiCodeParsing() throws {
        let json = """
        {
          "usage": {
            "limit": "100",
            "used": "47",
            "remaining": "53",
            "resetTime": "2026-12-01T00:00:00.000Z"
          },
          "usages": {
            "limit_5h": { "used_ratio": 0.23, "reset_time": "2026-11-26T05:00:00.000Z" },
            "limit_7d": { "used_ratio": 0.47, "reset_time": "2026-12-01T00:00:00.000Z" }
          }
        }
        """
        let snapshot = try KimiCodeProvider().parse(Data(json.utf8))

        #expect(snapshot.planName == "Kimi Code")

        let weekly = try #require(snapshot.quotas.first { $0.kind == .weekly })
        #expect(abs(weekly.remainingPercent - 53) < 0.001)

        let fiveHour = try #require(snapshot.quotas.first { $0.kind == .fiveHour })
        #expect(abs(fiveHour.remainingPercent - 77) < 0.001)
        #expect(fiveHour.resetDate != nil)
    }

    @Test func kimiCodeWithoutUsageThrows() {
        let json = """
        { "usages": {} }
        """
        #expect(throws: (any Error).self) {
            try KimiCodeProvider().parse(Data(json.utf8))
        }
    }
}
