import Foundation
import SQLite3

/// 读取 OpenCode 的本地会话库（只读）：
/// `~/.local/share/opencode/opencode.db` 的 `session_message` 表里，
/// assistant 消息带有 model / tokens / cost，是最精确的本地用量来源。
struct OpenCodeUsageScanner {
    var databasePath: String = ("~/.local/share/opencode/opencode.db" as NSString).expandingTildeInPath

    func scan(since: Date) -> [UsageRecord] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databasePath,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1_500)

        let sql = """
        SELECT sm.time_created,
               s.directory,
               json_extract(sm.data, '$.model.providerID'),
               json_extract(sm.data, '$.model.id'),
               json_extract(sm.data, '$.tokens.input'),
               json_extract(sm.data, '$.tokens.output'),
               json_extract(sm.data, '$.tokens.reasoning'),
               json_extract(sm.data, '$.tokens.cache.read'),
               json_extract(sm.data, '$.tokens.cache.write'),
               json_extract(sm.data, '$.cost')
        FROM session_message sm
        JOIN session_v2 s ON s.id = sm.session_id
        WHERE sm.type = 'assistant' AND sm.time_created >= ?
        ORDER BY sm.time_created ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1000))

        var records: [UsageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let millis = sqlite3_column_int64(statement, 0)
            let directory = columnText(statement, 1)
            let provider = columnText(statement, 2) ?? "unknown"
            let model = columnText(statement, 3) ?? "unknown"
            let input = Int(sqlite3_column_int64(statement, 4))
            let output = Int(sqlite3_column_int64(statement, 5))
            let reasoning = Int(sqlite3_column_int64(statement, 6))
            let cacheRead = Int(sqlite3_column_int64(statement, 7))
            let cacheWrite = Int(sqlite3_column_int64(statement, 8))
            let cost: Double? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 9)

            let totalInput = input
            let totalOutput = output + reasoning
            guard totalInput + totalOutput + cacheRead + cacheWrite > 0 else { continue }

            records.append(
                UsageRecord(
                    id: "opencode-\(millis)-\(records.count)",
                    date: Date(timeIntervalSince1970: TimeInterval(millis) / 1000),
                    provider: UsageRecord.canonicalProvider(provider, model: model),
                    model: model,
                    tool: "OpenCode",
                    project: directory.map { URL(fileURLWithPath: $0).lastPathComponent },
                    input: totalInput,
                    output: totalOutput,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    costUSD: cost
                )
            )
        }
        return records
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}
