import XCTest
@testable import Kakeibo

/// 復元候補ファイルの検査。ここが通らないファイルで現在のDBを上書きすると
/// データが失われるため、判定の正しさは重要。
final class BackupInspectionTests: XCTestCase {

    func test_正常なバックアップはokと判定される() throws {
        let tmp = try TempDatabase()
        tmp.db.closeConnection()
        assertInspection(tmp.path, is: .ok)
    }

    func test_SQLiteでないファイルはnotADatabase() throws {
        let url = try makeTempFile(name: "junk.sqlite", contents: "ただのテキスト")
        assertInspection(url.path, is: .notADatabase)
    }

    func test_存在しないファイルはnotADatabase() throws {
        let path = try makeTempPath(name: "missing.sqlite")
        assertInspection(path, is: .notADatabase)
    }

    func test_家計簿以外のSQLiteはnotKakeiboBackup() throws {
        let path = try makeTempPath(name: "other.sqlite")
        let other = try Database(path: path, migrate: false)
        XCTAssertTrue(other.exec("CREATE TABLE memo(id INTEGER PRIMARY KEY, body TEXT)"))
        XCTAssertTrue(other.exec("PRAGMA user_version = 3"))
        other.closeConnection()

        assertInspection(path, is: .notKakeiboBackup)
    }

    func test_バージョン未設定のSQLiteはnotKakeiboBackup() throws {
        let path = try makeTempPath(name: "v0.sqlite")
        let db = try Database(path: path, migrate: false)
        XCTAssertTrue(db.exec("CREATE TABLE accounts(id INTEGER PRIMARY KEY)"))
        XCTAssertTrue(db.exec("CREATE TABLE categories(id INTEGER PRIMARY KEY)"))
        XCTAssertTrue(db.exec("CREATE TABLE transactions(id INTEGER PRIMARY KEY)"))
        XCTAssertTrue(db.exec("CREATE TABLE settings(key TEXT PRIMARY KEY)"))
        db.closeConnection()

        assertInspection(path, is: .notKakeiboBackup, "user_version が 0 のままなら受け付けない")
    }

    func test_アプリより新しいスキーマはnewerSchema() throws {
        let tmp = try TempDatabase()
        XCTAssertTrue(tmp.db.exec("PRAGMA user_version = 99"))
        tmp.db.closeConnection()

        assertInspection(tmp.path, is: .newerSchema)
    }

    func test_古い世代のバックアップは復元を許す() throws {
        let tmp = try TempDatabase()
        XCTAssertTrue(tmp.db.exec("PRAGMA user_version = 1"))
        tmp.db.closeConnection()

        assertInspection(tmp.path, is: .ok, "復元後のマイグレーションで最新へ上がるため")
    }

    func test_検査はファイルを書き換えない() throws {
        let tmp = try TempDatabase()
        XCTAssertTrue(tmp.db.exec("PRAGMA user_version = 1"))
        tmp.db.closeConnection()

        _ = Database.inspectBackup(at: tmp.path)

        let reopened = try Database(path: tmp.path, migrate: false)
        let version = reopened.query("PRAGMA user_version").first?.int("user_version")
        reopened.closeConnection()
        XCTAssertEqual(version, 1, "検査でマイグレーションが走っていないこと")
    }

    // MARK: -

    private func assertInspection(_ path: String, is expected: BackupInspection,
                                  _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
        let actual = Database.inspectBackup(at: path)
        XCTAssertEqual(String(describing: actual), String(describing: expected),
                       message, file: file, line: line)
    }
}
