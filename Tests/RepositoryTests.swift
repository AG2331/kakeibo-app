import XCTest
@testable import Kakeibo

/// リポジトリの集計ロジック。特に「振替を収支に含めない」ことは
/// クレジットカードの二重計上防止の土台になっている。
final class RepositoryTests: XCTestCase {

    private var tmp: TempDatabase!
    private var tx: TransactionRepository!
    private var accounts: AccountRepository!
    private var cashId: Int64!
    private var bankId: Int64!
    private var cardId: Int64!

    override func setUpWithError() throws {
        tmp = try TempDatabase()
        tx = TransactionRepository(db: tmp.db)
        accounts = AccountRepository(db: tmp.db)

        cashId = accounts.all().first { $0.name == "現金" }!.id!
        XCTAssertTrue(accounts.insert(Account(name: "銀行", type: .bank,
                                              initialBalance: 100_000, sortOrder: 1)))
        bankId = accounts.all().first { $0.name == "銀行" }!.id!
        XCTAssertTrue(accounts.insert(Account(name: "カード", type: .credit, sortOrder: 2,
                                              closingDay: 15, paymentDay: 10,
                                              paymentAccountId: bankId)))
        cardId = accounts.all().first { $0.name == "カード" }!.id!
    }

    override func tearDown() {
        tmp = nil
        super.tearDown()
    }

    // MARK: - 収支集計

    func test_収支集計は収入と支出だけを数える() {
        XCTAssertTrue(tx.insert(TxRecord(type: .income, amount: 300_000, date: "2026-09-10",
                                         accountId: bankId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 1_200, date: "2026-09-02",
                                         accountId: cashId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 50_000, date: "2026-09-05",
                                         accountId: bankId, toAccountId: cashId)))

        let summary = tx.summary(start: "2026-09-01", end: "2026-09-30")
        XCTAssertEqual(summary.income, 300_000)
        XCTAssertEqual(summary.expense, 1_200)
        XCTAssertEqual(summary.net, 298_800)
    }

    func test_カード引き落としの振替は支出に計上されない() {
        // 購入時に支出として計上する
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 12_000, date: "2026-08-05",
                                         accountId: cardId)))
        // 引き落としは振替として記録する
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 12_000, date: "2026-09-10",
                                         accountId: bankId, toAccountId: cardId)))

        XCTAssertEqual(tx.summary(start: "2026-08-01", end: "2026-08-31").expense, 12_000)
        XCTAssertEqual(tx.summary(start: "2026-09-01", end: "2026-09-30").expense, 0,
                       "引き落とし月に二重計上されないこと")
    }

    func test_期間外の取引は集計されない() {
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 500, date: "2026-08-31",
                                         accountId: cashId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 700, date: "2026-10-01",
                                         accountId: cashId)))
        XCTAssertEqual(tx.summary(start: "2026-09-01", end: "2026-09-30").expense, 0)
    }

    // MARK: - カード請求額（正味利用額）

    func test_正味利用額は支出の合計() {
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 12_000, date: "2026-08-05",
                                         accountId: cardId)))
        XCTAssertEqual(tx.netUsage(accountId: cardId, start: "2026-07-16", end: "2026-08-15"), 12_000)
    }

    func test_カードへの返金は請求額から差し引かれる() {
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 12_000, date: "2026-08-05",
                                         accountId: cardId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .income, amount: 5_000, date: "2026-08-10",
                                         accountId: cardId)))
        XCTAssertEqual(tx.netUsage(accountId: cardId, start: "2026-07-16", end: "2026-08-15"), 7_000)
    }

    func test_他の口座の利用は請求額に含まれない() {
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 9_999, date: "2026-08-05",
                                         accountId: cashId)))
        XCTAssertEqual(tx.netUsage(accountId: cardId, start: "2026-07-16", end: "2026-08-15"), 0)
    }

    // MARK: - 支払済額

    func test_締め日より後の振替だけを支払済とみなす() {
        // 前サイクルの支払い（締め日より前）
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 3_000, date: "2026-08-10",
                                         accountId: bankId, toAccountId: cardId)))
        // 今回の支払い（締め日より後）
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 12_000, date: "2026-09-10",
                                         accountId: bankId, toAccountId: cardId)))

        XCTAssertEqual(tx.transferInSum(accountId: cardId, since: "2026-08-15"), 12_000)
    }

    func test_カードから出ていく振替は支払済に数えない() {
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 1_000, date: "2026-09-10",
                                         accountId: cardId, toAccountId: bankId)))
        XCTAssertEqual(tx.transferInSum(accountId: cardId, since: "2026-08-15"), 0)
    }

    // MARK: - 残高

    func test_残高は初期残高と入出金から計算される() {
        XCTAssertTrue(tx.insert(TxRecord(type: .income, amount: 200_000, date: "2026-09-10",
                                         accountId: bankId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 30_000, date: "2026-09-11",
                                         accountId: bankId)))
        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 50_000, date: "2026-09-12",
                                         accountId: bankId, toAccountId: cashId)))

        XCTAssertEqual(accounts.balance(id: bankId), 100_000 + 200_000 - 30_000 - 50_000)
        XCTAssertEqual(accounts.balance(id: cashId), 50_000, "振替先には入金される")
    }

    func test_カード利用で残高がマイナス_未払い残高になる() {
        XCTAssertTrue(tx.insert(TxRecord(type: .expense, amount: 12_000, date: "2026-08-05",
                                         accountId: cardId)))
        XCTAssertEqual(accounts.balance(id: cardId), -12_000)

        XCTAssertTrue(tx.insert(TxRecord(type: .transfer, amount: 12_000, date: "2026-09-10",
                                         accountId: bankId, toAccountId: cardId)))
        XCTAssertEqual(accounts.balance(id: cardId), 0, "引き落としで未払いが解消される")
    }

    // MARK: - 参照の検出

    func test_引き落とし元に指定されている口座を検出する() {
        XCTAssertEqual(accounts.paymentSourceOf(id: bankId), ["カード"])
        XCTAssertEqual(accounts.paymentSourceOf(id: cashId), [])
    }

    func test_仮想口座の親を検出する() {
        XCTAssertTrue(accounts.insert(Account(name: "貯金用", type: .bank, sortOrder: 3,
                                              parentId: bankId)))
        XCTAssertEqual(accounts.childNames(id: bankId), ["貯金用"])
        XCTAssertEqual(accounts.childCount(id: bankId), 1)
    }

    func test_定期取引が使っている口座とカテゴリを検出する() {
        let recurring = RecurringRepository(db: tmp.db)
        let categoryId = CategoryRepository(db: tmp.db).all().first { $0.name == "住居費" }!.id!
        XCTAssertTrue(recurring.insert(RecurringRule(
            type: .expense, amount: 80_000, categoryId: categoryId, accountId: bankId,
            memo: "家賃", frequency: .monthly, interval: 1, nextDate: "2026-10-01")))

        XCTAssertEqual(recurring.usingAccount(id: bankId), ["家賃"])
        XCTAssertEqual(recurring.usingCategory(id: categoryId), ["家賃"])
        XCTAssertEqual(recurring.usingAccount(id: cashId), [])
    }

    func test_カテゴリに設定された予算の月数を数える() {
        let budgets = BudgetRepository(db: tmp.db)
        let categoryId = CategoryRepository(db: tmp.db).all().first { $0.name == "食費" }!.id!
        XCTAssertTrue(budgets.set(yearMonth: "2026-09", categoryId: categoryId, amount: 20_000))
        XCTAssertTrue(budgets.set(yearMonth: "2026-10", categoryId: categoryId, amount: 25_000))

        XCTAssertEqual(budgets.countByCategory(id: categoryId), 2)
    }

    func test_予算に0を設定すると削除される() {
        let budgets = BudgetRepository(db: tmp.db)
        let categoryId = CategoryRepository(db: tmp.db).all().first { $0.name == "食費" }!.id!
        XCTAssertTrue(budgets.set(yearMonth: "2026-09", categoryId: categoryId, amount: 20_000))
        XCTAssertTrue(budgets.set(yearMonth: "2026-09", categoryId: categoryId, amount: 0))

        XCTAssertEqual(budgets.countByCategory(id: categoryId), 0)
    }
}
