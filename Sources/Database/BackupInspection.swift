import Foundation

/// 復元候補ファイルの検査結果。
enum BackupInspection {
    /// このアプリのDBとして復元してよい。
    case ok
    /// SQLite として開けない、または壊れている。
    case notADatabase
    /// SQLite ではあるが、この家計簿アプリのバックアップではない。
    case notKakeiboBackup
    /// アプリが知らない新しいスキーマ（新しいバージョンのアプリで作られた）。
    case newerSchema
}

/// 復元の結果。失敗時も現在のデータは保持される。
enum RestoreResult {
    case success
    case invalidFile
    case notKakeiboBackup
    case newerSchema
    case failed(String)

    /// ユーザーに見せる説明文。
    var message: String {
        switch self {
        case .success:
            return "復元しました。"
        case .invalidFile:
            return "このファイルはデータベースとして読み取れません。現在のデータはそのまま残っています。"
        case .notKakeiboBackup:
            return "この家計簿アプリのバックアップではありません。現在のデータはそのまま残っています。"
        case .newerSchema:
            return "新しいバージョンのアプリで作られたバックアップです。アプリを更新してから復元してください。"
        case .failed(let detail):
            return "復元に失敗しました。現在のデータは元に戻しています。（\(detail)）"
        }
    }
}

extension Database {
    /// 復元に使ってよいファイルかを、現在のDBに触れずに検査する。
    /// マイグレーションは行わずに開くため、検査自体がファイルを書き換えることはない。
    static func inspectBackup(at path: String) -> BackupInspection {
        guard FileManager.default.fileExists(atPath: path),
              let probe = try? Database(path: path, migrate: false) else {
            return .notADatabase
        }

        // 壊れたファイルや SQLite でないファイルはここで弾かれる（結果が返らない or ok 以外）。
        guard probe.query("PRAGMA integrity_check").first?
            .string("integrity_check") == "ok" else {
            return .notADatabase
        }

        let required = ["accounts", "categories", "transactions", "settings"]
        let names = Set(probe.query(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).compactMap { $0.string("name") })
        guard required.allSatisfy(names.contains) else { return .notKakeiboBackup }

        // v1〜現行までの古いバックアップは復元後のマイグレーションで最新へ上がる。
        let version = probe.query("PRAGMA user_version").first?.int("user_version") ?? 0
        guard version >= 1 else { return .notKakeiboBackup }
        guard version <= Int(Database.schemaVersion) else { return .newerSchema }

        return .ok
    }
}
