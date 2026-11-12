import Foundation
import SQLite3

enum OpenCodeSessionSource {
    static func scan(
        databaseURL: URL? = nil,
        providerIsRunning: Bool,
        now: Date = .now
    ) -> [AgentSession] {
        let url = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)

        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let sql = """
            SELECT id, directory, title, time_created, time_updated
            FROM session
            WHERE time_updated >= ?
            ORDER BY time_updated DESC
            LIMIT 36
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970 * 1_000))

        var sessions: [AgentSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0),
                  let directory = text(statement, column: 1) else {
                continue
            }
            let title = text(statement, column: 2) ?? "OpenCode 会话"
            let createdAt = Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 3) / 1_000
            )
            let updatedAt = Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 4) / 1_000
            )
            let messages = events(
                database: database,
                sessionID: id,
                table: "message",
                limit: 200
            )
            let parts = events(
                database: database,
                sessionID: id,
                table: "part",
                limit: 800
            )
            let record = OpenCodeSessionRecord(
                id: id,
                directory: directory,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messages: messages,
                parts: parts
            )
            if let session = OpenCodeAdapter.parse(
                record: record,
                fileURL: url,
                providerIsRunning: providerIsRunning,
                now: now
            ) {
                sessions.append(session)
            }
        }
        return sessions
    }

    private static func events(
        database: OpaquePointer,
        sessionID: String,
        table: String,
        limit: Int
    ) -> [OpenCodeEvent] {
        guard table == "message" || table == "part" else {
            return []
        }
        let messageIDColumn = table == "part" ? "message_id" : "NULL"
        let sql = """
            SELECT id, time_created, data, \(messageIDColumn)
            FROM \(table)
            WHERE session_id = ?
            ORDER BY time_created DESC
            LIMIT \(limit)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(
            statement,
            1,
            (sessionID as NSString).utf8String,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )

        var events: [OpenCodeEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0),
                  let json = text(statement, column: 2),
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else {
                continue
            }
            events.append(OpenCodeEvent(
                id: id,
                date: Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 1) / 1_000
                ),
                data: dictionary,
                messageID: text(statement, column: 3)
            ))
        }
        return events
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }
}
