import Foundation
import SQLite3

/// DB を開けない・マイグレーションできないなど、起動を妨げる失敗。
enum DatabaseError: LocalizedError {
    case cannotOpen(String)
    case migrationFailed(version: Int32, detail: String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let detail):
            return "データベースを開けませんでした。（\(detail)）"
        case .migrationFailed(let version, let detail):
            return "データベースの更新（v\(version)）に失敗しました。（\(detail)）"
        }
    }
}

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

/// 書き込み(INSERT/UPDATE/DELETE)の結果。rowId は INSERT 時のみ意味を持つ。
struct WriteResult {
    let ok: Bool
    let rowId: Int64
    let message: String?
    /// 外部キー制約違反（他のデータから参照されているため削除・更新できない）か。
    let isConstraintViolation: Bool

    static let failure = WriteResult(ok: false, rowId: 0, message: nil,
                                     isConstraintViolation: false)
}

/// libsqlite3 を直接利用する薄いラッパ。
final class Database {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// path: ファイルパス。":memory:" でインメモリ（テスト用）。
    /// migrate: false にするとマイグレーションを行わない（復元候補ファイルの検査用）。
    init(path: String, migrate: Bool = true) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw DatabaseError.cannotOpen(lastErrorMessage() ?? "unknown")
        }
        exec("PRAGMA foreign_keys = ON")
        if migrate { try migrateIfNeeded() }
    }

    deinit { sqlite3_close(db) }

    /// 接続を明示的に閉じる（バックアップ復元時にファイルを差し替える前に呼ぶ）。
    func closeConnection() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - 実行系

    /// DDL や PRAGMA など、結果を返さない文。成功したかを返す。
    @discardableResult
    func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// INSERT/UPDATE/DELETE。成否と、INSERT 時の lastInsertRowId を返す。
    @discardableResult
    func run(_ sql: String, _ args: [SQLValue] = []) -> WriteResult {
        guard let stmt = prepare(sql, args) else {
            return WriteResult(ok: false, rowId: 0, message: lastErrorMessage(),
                               isConstraintViolation: false)
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            // 拡張エラーコードの下位8bitが SQLITE_CONSTRAINT なら制約違反。
            let extended = sqlite3_extended_errcode(db)
            let isConstraint = (extended & 0xFF) == SQLITE_CONSTRAINT
            return WriteResult(ok: false, rowId: 0, message: lastErrorMessage(),
                               isConstraintViolation: isConstraint)
        }
        return WriteResult(ok: true, rowId: sqlite3_last_insert_rowid(db),
                           message: nil, isConstraintViolation: false)
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

    /// 直近の SQLite エラーメッセージ。マイグレーション側からも使う。
    func lastErrorMessage() -> String? {
        db.map { String(cString: sqlite3_errmsg($0)) }
    }
}
