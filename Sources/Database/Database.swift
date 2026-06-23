import Foundation
import SQLite3

/// バインド用の値。
enum SQLValue {
    case int(Int64)
    case text(String)
    case null

    init(_ v: Int?) { self = v.map { .int(Int64($0)) } ?? .null }
    init(_ v: Int64?) { self = v.map { .int($0) } ?? .null }
    init(_ v: String?) { self = v.map { .text($0) } ?? .null }
}

/// 1行の結果。カラム名でアクセスする。
struct Row {
    let values: [String: Any]

    func int64(_ key: String) -> Int64? { values[key] as? Int64 }
    func int(_ key: String) -> Int? { (values[key] as? Int64).map(Int.init) }
    func string(_ key: String) -> String? { values[key] as? String }
}

/// libsqlite3 を直接利用する薄いラッパ。
final class Database {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// path: ファイルパス。":memory:" でインメモリ（テスト用）。
    init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw error("open failed")
        }
        exec("PRAGMA foreign_keys = ON")
        try migrateIfNeeded()
    }

    deinit { sqlite3_close(db) }

    // MARK: - 実行系

    /// DDL や PRAGMA など、結果を返さない文。
    func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// INSERT/UPDATE/DELETE。INSERT 時は lastInsertRowId を返す。
    @discardableResult
    func run(_ sql: String, _ args: [SQLValue] = []) -> Int64 {
        guard let stmt = prepare(sql, args) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    /// SELECT。行の配列を返す。
    func query(_ sql: String, _ args: [SQLValue] = []) -> [Row] {
        guard let stmt = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(stmt) }

        let columnCount = sqlite3_column_count(stmt)
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var dict: [String: Any] = [:]
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    dict[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    dict[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    dict[name] = String(cString: sqlite3_column_text(stmt, i))
                default:
                    break // NULL は格納しない
                }
            }
            rows.append(Row(values: dict))
        }
        return rows
    }

    // MARK: - 内部

    private func prepare(_ sql: String, _ args: [SQLValue]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        for (idx, value) in args.enumerated() {
            let pos = Int32(idx + 1)
            switch value {
            case .int(let v):
                sqlite3_bind_int64(stmt, pos, v)
            case .text(let v):
                sqlite3_bind_text(stmt, pos, v, -1, Database.transient)
            case .null:
                sqlite3_bind_null(stmt, pos)
            }
        }
        return stmt
    }

    private func error(_ msg: String) -> NSError {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? ""
        return NSError(domain: "Database", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: "\(msg): \(detail)"])
    }
}
