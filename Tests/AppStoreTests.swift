import XCTest
@testable import Kakeibo

/// AppStore の振る舞い。削除ガード・請求状況・復元といった、
/// 失敗しても黙って進んでしまうと被害が大きい箇所を中心に確認する。
@MainActor
final class AppStoreTests: XCTestCase {

    private var tmp: TempDatabase!
    private var store: AppStore!
    private var cashId: Int64!
    private var bankId: Int64!
    private var cardId: Int64!

    override func setUpWithError() throws {
        tmp = try TempDatabase()
        store = AppStore(db: tmp.db, dbPath: tmp.path)

        cashId = store.accountList.first { $0.name == "現金" }!.id!
        XCTAssertNil(store.saveAccount(Account(name: "銀行", type: .bank, initialBalance: 500_000)))
        bankId = store.accountList.first { $0.name == "銀行" }!.id!
        XCTAssertNil(store.saveAccount(Account(name: "カード", type: .credit,
                                               closingDay: 15, paymentDay: 10,
                                               paymentMonthOffset: 1, paymentAccountId: bankId)))
        cardId = store.accountList.first { $0.name == "カード" }!.id!
    }

    override func tearDown() {
        store = nil
        tmp = nil
        super.tearDown()
    }

    // MARK: - 削除ガード

    func test_取引で使われている口座は理由付きで削除を拒む() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_000, date: "2026-09-01",
                                         accountId: cashId)))
        let account = store.accountList.first { $0.id == cashId }!

        let reason = store.deleteAccount(account)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("取引"), reason ?? "")
        XCTAssertTrue(store.accountList.contains { $0.id == cashId }, "一覧に残ること")
    }

    func test_引き落とし元の口座はカード名を示して削除を拒む() {
        let bank = store.accountList.first { $0.id == bankId }!
        let reason = store.deleteAccount(bank)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("カード"), reason ?? "")
    }

    func test_仮想口座を持つ親は子の名前を示して削除を拒む() {
        XCTAssertNil(store.saveAccount(Account(name: "貯金用", type: .bank, parentId: bankId)))
        let bank = store.accountList.first { $0.id == bankId }!

        let reason = store.deleteAccount(bank)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("貯金用"), reason ?? "")
    }

    func test_定期取引で使われている口座は削除を拒む() {
        XCTAssertNil(store.saveAccount(Account(name: "サブ銀行", type: .bank)))
        let subId = store.accountList.first { $0.name == "サブ銀行" }!.id!
        XCTAssertNil(store.saveRecurring(RecurringRule(
            type: .expense, amount: 80_000, accountId: subId, memo: "家賃",
            frequency: .monthly, interval: 1, nextDate: "2027-01-01")))

        let reason = store.deleteAccount(store.accountList.first { $0.id == subId }!)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("定期取引"), reason ?? "")
    }

    func test_参照のない口座は削除できる() {
        XCTAssertNil(store.saveAccount(Account(name: "未使用", type: .bank)))
        let unused = store.accountList.first { $0.name == "未使用" }!

        XCTAssertNil(store.deleteAccount(unused), "理由なし = 削除成功")
        XCTAssertFalse(store.accountList.contains { $0.name == "未使用" })
    }

    func test_予算が設定されたカテゴリは削除を拒む() {
        let category = store.allCategories.first { $0.name == "娯楽" }!
        XCTAssertNil(store.setBudget(categoryId: category.id, amount: 30_000))

        let reason = store.deleteCategory(category)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("予算"), reason ?? "")
    }

    func test_参照のないカテゴリは削除できる() {
        XCTAssertNil(store.saveCategory(Category(name: "テスト用", type: .expense)))
        let category = store.allCategories.first { $0.name == "テスト用" }!

        XCTAssertNil(store.deleteCategory(category))
        XCTAssertFalse(store.allCategories.contains { $0.name == "テスト用" })
    }

    // MARK: - クレジットカードの請求状況

    /// 締め日15日・支払日翌月10日。締め済み期間に12,000円、進行中期間に3,500円。
    private func seedCardUsage() {
        let closed = CreditCardCycle.lastClosedPeriod(closingDay: 15)
        let open = CreditCardCycle.openPeriod(closingDay: 15)
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 12_000, date: closed.end,
                                         accountId: cardId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 3_500, date: open.start,
                                         accountId: cardId)))
    }

    func test_締め済みの利用額が請求額になる() {
        seedCardUsage()
        let info = store.creditCardStatements[cardId]
        XCTAssertEqual(info?.dueAmount, 12_000)
        XCTAssertEqual(info?.upcomingAmount, 3_500, "進行中サイクルは別勘定")
        XCTAssertEqual(info?.outstandingAmount, 15_500, "未精算額は利用分すべて")
        XCTAssertEqual(info?.isSettled, false)
    }

    func test_引き落としを記録すると請求は支払い済みになる() {
        seedCardUsage()
        let due = store.creditCardStatements[cardId]!

        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: due.dueAmount,
                                         date: due.dueDate, accountId: bankId,
                                         toAccountId: cardId)))

        let after = store.creditCardStatements[cardId]
        XCTAssertEqual(after?.dueAmount, 0)
        XCTAssertEqual(after?.isSettled, true)
        XCTAssertEqual(after?.outstandingAmount, 3_500, "進行中サイクル分だけが残る")
        XCTAssertEqual(after?.nextAmount, 3_500, "次に支払うのは進行中サイクル分")
        XCTAssertEqual(after?.nextDate, after?.upcomingDueDate)
    }

    func test_支払い済みでも月次の支出は二重計上されない() {
        seedCardUsage()
        let due = store.creditCardStatements[cardId]!
        let monthOfPayment = String(due.dueDate.prefix(7))

        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: due.dueAmount,
                                         date: due.dueDate, accountId: bankId,
                                         toAccountId: cardId)))

        let expense = store.transactions.summary(start: "\(monthOfPayment)-01",
                                                 end: "\(monthOfPayment)-31").expense
        XCTAssertEqual(expense, 0, "引き落とし月に支出は発生しない")
    }

    func test_支払日を過ぎた未払いは期限超過になる() {
        // 支払日が確実に過去になるよう、締め済み期間の利用だけを入れる
        let closed = CreditCardCycle.lastClosedPeriod(closingDay: 15)
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 12_000, date: closed.end,
                                         accountId: cardId)))
        let info = store.creditCardStatements[cardId]!

        XCTAssertEqual(info.isOverdue, info.dueDate < Dates.today(),
                       "支払日が過ぎていれば期限超過として示す")
        if info.isOverdue { XCTAssertGreaterThan(info.dueAmount, 0) }
    }

    func test_返金は請求額から差し引かれる() {
        let closed = CreditCardCycle.lastClosedPeriod(closingDay: 15)
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 12_000, date: closed.end,
                                         accountId: cardId)))
        XCTAssertNil(store.save(TxRecord(type: .income, amount: 5_000, date: closed.end,
                                         accountId: cardId)))

        XCTAssertEqual(store.creditCardStatements[cardId]?.dueAmount, 7_000)
    }

    func test_締め日未設定のカードは請求情報を持たない() {
        XCTAssertNil(store.saveAccount(Account(name: "設定前カード", type: .credit)))
        let id = store.accountList.first { $0.name == "設定前カード" }!.id!
        XCTAssertNil(store.creditCardStatements[id])
    }

    // MARK: - 総資産

    func test_引き落としでは総資産が変わらない() {
        seedCardUsage()
        let before = store.accountOverview().grandTotal
        let due = store.creditCardStatements[cardId]!

        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: due.dueAmount,
                                         date: due.dueDate, accountId: bankId,
                                         toAccountId: cardId)))

        XCTAssertEqual(store.accountOverview().grandTotal, before,
                       "負債の返済は資産の移動であって増減ではない")
    }

    func test_総資産は仮想口座を重複して数えない() {
        XCTAssertNil(store.saveAccount(Account(name: "貯金用", type: .bank,
                                               initialBalance: 50_000, parentId: bankId)))
        let overview = store.accountOverview()
        let parent = overview.nodes.first { $0.account.id == bankId }!

        XCTAssertEqual(parent.ownBalance, 500_000)
        XCTAssertEqual(parent.total, 550_000)
        XCTAssertEqual(overview.grandTotal, 550_000, "親の合計に子が含まれ、二重に足されない")
    }

    // MARK: - バックアップ復元

    func test_不正なファイルを選んでも現在のデータが残る() throws {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_234, date: "2026-09-01",
                                         accountId: cashId)))
        let before = store.monthTransactions.count

        let junk = try makeTempFile(name: "junk.sqlite", contents: "これはDBではない")
        let result = store.restore(from: junk)

        guard case .invalidFile = result else {
            return XCTFail("invalidFile を期待したが \(result)")
        }
        XCTAssertEqual(store.accountList.count, 3, "口座が消えていないこと")
        XCTAssertEqual(store.transactions.range().count, before, "取引が消えていないこと")
    }

    func test_家計簿以外のSQLiteは復元せずデータを残す() throws {
        let path = try makeTempPath(name: "other.sqlite")
        let other = try Database(path: path, migrate: false)
        XCTAssertTrue(other.exec("CREATE TABLE memo(id INTEGER PRIMARY KEY)"))
        XCTAssertTrue(other.exec("PRAGMA user_version = 2"))
        other.closeConnection()

        let result = store.restore(from: URL(fileURLWithPath: path))

        guard case .notKakeiboBackup = result else {
            return XCTFail("notKakeiboBackup を期待したが \(result)")
        }
        XCTAssertEqual(store.accountList.count, 3)
    }

    func test_新しいスキーマのバックアップは拒否する() throws {
        let backup = try TempDatabase()
        XCTAssertTrue(backup.db.exec("PRAGMA user_version = 99"))
        backup.db.closeConnection()

        let result = store.restore(from: URL(fileURLWithPath: backup.path))

        guard case .newerSchema = result else {
            return XCTFail("newerSchema を期待したが \(result)")
        }
    }

    func test_正しいバックアップは復元されデータが入れ替わる() throws {
        // 別のDBに目印の取引を入れてバックアップとする
        let backup = try TempDatabase()
        let backupAccounts = AccountRepository(db: backup.db)
        let backupCash = backupAccounts.all().first!.id!
        XCTAssertTrue(TransactionRepository(db: backup.db).insert(
            TxRecord(type: .income, amount: 999_999, date: "2026-09-07",
                     accountId: backupCash, memo: "目印")))
        backup.db.closeConnection()

        let result = store.restore(from: URL(fileURLWithPath: backup.path))

        guard case .success = result else {
            return XCTFail("success を期待したが \(result)")
        }
        XCTAssertTrue(store.transactions.range().contains { $0.memo == "目印" })
        XCTAssertFalse(store.accountList.contains { $0.name == "カード" },
                       "復元元のデータに入れ替わること")
    }

    // MARK: - 定期取引

    func test_期日を過ぎた定期取引は取引を生成し次回日を進める() {
        XCTAssertNil(store.saveRecurring(RecurringRule(
            type: .expense, amount: 80_000,
            categoryId: store.allCategories.first { $0.name == "住居費" }?.id,
            accountId: bankId, memo: "家賃", frequency: .monthly, interval: 1,
            nextDate: "2020-01-01")))

        XCTAssertTrue(store.transactions.range().contains { $0.memo == "家賃" },
                      "期日を過ぎた分が計上されること")
        let rule = store.recurringRules.first { $0.memo == "家賃" }!
        XCTAssertGreaterThan(rule.nextDate, Dates.today(), "次回予定日が未来に進むこと")
    }

    // MARK: - CSV

    func test_CSVに取引が出力される() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_200, date: "2026-09-02",
                                         accountId: cashId, memo: "コンビニ")))
        let csv = store.exportCSV()

        XCTAssertTrue(csv.hasPrefix("日付,種別,金額,カテゴリ,口座,振替先,メモ"))
        XCTAssertTrue(csv.contains("2026-09-02,支出,1200"))
        XCTAssertTrue(csv.contains("コンビニ"))
        XCTAssertTrue(csv.contains("\r\n"), "CSVの標準に合わせてCRLF区切りであること")
    }

    func test_CSVファイルはBOM付きで書き出される() throws {
        let url = try XCTUnwrap(store.makeCSVFile())
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF],
                       "Excel（日本語環境）で文字化けしないこと")
    }
}
