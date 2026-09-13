import XCTest
@testable import Kakeibo

/// DB層: 書き込みエラーの検知とマイグレーション。
/// 握り潰すと「削除したのに残る」「空データで起動する」といった不具合になるため、
/// 失敗がきちんと失敗として返ることを確かめる。
final class DatabaseTests: XCTestCase {

    func test_新規DBは最新スキーマまで上がる() throws {
        let tmp = try TempDatabase()
        let version = tmp.db.query("PRAGMA user_version").first?.int("user_version")
        XCTAssertEqual(version.map(Int32.init), Database.schemaVersion)
    }

    func test_新規DBに既定のカテゴリと現金口座が入る() throws {
        let tmp = try TempDatabase()
        let accounts = AccountRepository(db: tmp.db).all()
        let categories = CategoryRepository(db: tmp.db).all()
        XCTAssertEqual(accounts.map(\.name), ["現金"])
        XCTAssertFalse(categories.isEmpty)
        XCTAssertTrue(categories.contains { $0.name == "食費" && $0.type == .expense })
        XCTAssertTrue(categories.contains { $0.name == "給与" && $0.type == .income })
    }

    func test_必要なインデックスが作られている() throws {
        let tmp = try TempDatabase()
        let indexes = Set(tmp.db.query("SELECT name FROM sqlite_master WHERE type='index'")
            .compactMap { $0.string("name") })
        XCTAssertTrue(indexes.contains("idx_tx_date"))
        XCTAssertTrue(indexes.contains("idx_tx_account"))
        XCTAssertTrue(indexes.contains("idx_tx_to_account"), "残高計算が振替先で全表走査しないこと")
    }

    func test_残高計算のクエリが振替先インデックスを使う() throws {
        let tmp = try TempDatabase()
        let plan = tmp.db.query("""
            EXPLAIN QUERY PLAN SELECT SUM(amount) FROM transactions
            WHERE (type='income' AND account_id=1) OR (type='transfer' AND to_account_id=1)
            """).compactMap { $0.string("detail") }.joined(separator: " / ")
        XCTAssertTrue(plan.contains("idx_tx_to_account"), "実行計画: \(plan)")
    }

    // MARK: - 書き込みの成否

    func test_INSERTは成功として返りrowIdを持つ() throws {
        let tmp = try TempDatabase()
        let result = tmp.db.run(
            "INSERT INTO accounts(name,type,initial_balance,sort_order,archived) VALUES(?,?,?,?,?)",
            [.text("銀行"), .text("bank"), .int(0), .int(1), .int(0)])
        XCTAssertTrue(result.ok)
        XCTAssertGreaterThan(result.rowId, 0)
        XCTAssertNil(result.message)
    }

    func test_参照されている行のDELETEは制約違反として返る() throws {
        let tmp = try TempDatabase()
        let accounts = AccountRepository(db: tmp.db)
        XCTAssertTrue(accounts.insert(Account(name: "銀行", type: .bank, sortOrder: 1)))
        let bankId = accounts.all().first { $0.name == "銀行" }!.id!
        XCTAssertTrue(accounts.insert(Account(name: "カード", type: .credit, sortOrder: 2,
                                              closingDay: 15, paymentDay: 10,
                                              paymentAccountId: bankId)))

        let result = tmp.db.run("DELETE FROM accounts WHERE id=?", [.int(bankId)])
        XCTAssertFalse(result.ok, "引き落とし元に指定された口座は削除できない")
        XCTAssertTrue(result.isConstraintViolation)
        XCTAssertNotNil(result.message)
    }

    func test_参照のない行は削除できる() throws {
        let tmp = try TempDatabase()
        let accounts = AccountRepository(db: tmp.db)
        XCTAssertTrue(accounts.insert(Account(name: "使っていない口座", type: .bank, sortOrder: 9)))
        let id = accounts.all().first { $0.name == "使っていない口座" }!.id!
        XCTAssertTrue(accounts.delete(id: id))
        XCTAssertNil(accounts.all().first { $0.id == id })
    }

    func test_不正なSQLは失敗として返る() throws {
        let tmp = try TempDatabase()
        let result = tmp.db.run("DELETE FROM 存在しないテーブル WHERE id=1")
        XCTAssertFalse(result.ok)
        XCTAssertNotNil(result.message)
    }

    // MARK: - マイグレーションの失敗検知

    func test_書き込めないDBではマイグレーションが失敗として投げられる() throws {
        let path = try makeTempPath(name: "readonly.sqlite")
        _ = try Database(path: path, migrate: false)     // 空のDBを作る
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        }

        XCTAssertThrowsError(try Database(path: path)) { error in
            guard case DatabaseError.migrationFailed = error else {
                return XCTFail("migrationFailed を期待したが \(error)")
            }
        }
    }

    func test_SQLiteでないファイルは開こうとすると失敗する() throws {
        let url = try makeTempFile(name: "junk.sqlite", contents: "これはデータベースではありません")
        XCTAssertThrowsError(try Database(path: url.path)) { error in
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func test_マイグレーション済みのDBを開き直しても壊れない() throws {
        let path = try makeTempPath(name: "reopen.sqlite")
        do {
            let first = try Database(path: path)
            XCTAssertTrue(AccountRepository(db: first).insert(
                Account(name: "貯金", type: .bank, sortOrder: 5)))
            first.closeConnection()
        }
        let second = try Database(path: path)
        XCTAssertTrue(AccountRepository(db: second).all().contains { $0.name == "貯金" })
        second.closeConnection()
    }
}
