import XCTest
@testable import Kakeibo

/// 口座詳細（取引履歴と残高推移）の集計。
@MainActor
final class AccountDetailTests: XCTestCase {

    private var tmp: TempDatabase!
    private var store: AppStore!
    private var bankId: Int64!
    private var savingsId: Int64!
    private var cashId: Int64!

    override func setUpWithError() throws {
        tmp = try TempDatabase()
        store = AppStore(db: tmp.db, dbPath: tmp.path)
        cashId = store.accountList.first { $0.name == "現金" }!.id!
        XCTAssertNil(store.saveAccount(Account(name: "銀行", type: .bank, initialBalance: 100_000)))
        bankId = store.accountList.first { $0.name == "銀行" }!.id!
        XCTAssertNil(store.saveAccount(Account(name: "貯金用", type: .bank, parentId: bankId)))
        savingsId = store.accountList.first { $0.name == "貯金用" }!.id!
    }

    override func tearDown() {
        store = nil
        tmp = nil
        super.tearDown()
    }

    // MARK: - 取引履歴

    func test_その口座の取引だけを集める() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_000, date: "2026-09-01",
                                         accountId: bankId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 2_000, date: "2026-09-02",
                                         accountId: cashId)))

        let items = store.transactions(ofAccount: bankId)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.amount, 1_000)
    }

    func test_振替は出金元からも振替先からも見える() {
        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: 50_000, date: "2026-09-05",
                                         accountId: bankId, toAccountId: savingsId)))

        XCTAssertEqual(store.transactions(ofAccount: bankId).count, 1, "出ていく側にも現れる")
        XCTAssertEqual(store.transactions(ofAccount: savingsId).count, 1, "入ってくる側にも現れる")
    }

    func test_取引履歴は新しい順に並ぶ() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 100, date: "2026-09-01",
                                         accountId: bankId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 200, date: "2026-09-20",
                                         accountId: bankId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 300, date: "2026-09-10",
                                         accountId: bankId)))

        XCTAssertEqual(store.transactions(ofAccount: bankId).map(\.date),
                       ["2026-09-20", "2026-09-10", "2026-09-01"])
    }

    // MARK: - 任意時点の残高

    func test_指定日までの残高を計算できる() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 30_000, date: "2026-08-10",
                                         accountId: bankId)))
        XCTAssertNil(store.save(TxRecord(type: .income, amount: 200_000, date: "2026-09-10",
                                         accountId: bankId)))

        XCTAssertEqual(store.accounts.balance(id: bankId, asOf: "2026-08-31"), 70_000,
                       "8月末時点では9月の入金を含まない")
        XCTAssertEqual(store.accounts.balance(id: bankId, asOf: "2026-09-30"), 270_000)
        XCTAssertEqual(store.accounts.balance(id: bankId), 270_000, "asOf 無しは全期間")
    }

    func test_指定日より後の取引は残高に含めない() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 5_000, date: "2026-09-20",
                                         accountId: bankId)))
        XCTAssertEqual(store.accounts.balance(id: bankId, asOf: "2026-09-19"), 100_000)
        XCTAssertEqual(store.accounts.balance(id: bankId, asOf: "2026-09-20"), 95_000)
    }

    // MARK: - 残高推移

    func test_残高推移は月ごとの点を返す() {
        store.selectedMonth = Dates.parse("2026-09-15")
        let points = store.balanceTrend(accountId: bankId, months: 6)

        XCTAssertEqual(points.count, 6)
        XCTAssertEqual(points.map(\.label), ["4月", "5月", "6月", "7月", "8月", "9月"])
    }

    func test_残高推移が入出金を反映する() {
        XCTAssertNil(store.save(TxRecord(type: .income, amount: 200_000, date: "2026-08-10",
                                         accountId: bankId)))
        store.selectedMonth = Dates.parse("2026-09-15")
        store.reload()

        let points = store.balanceTrend(accountId: bankId, months: 6)
        let july = points.first { $0.label == "7月" }!
        let august = points.first { $0.label == "8月" }!

        XCTAssertEqual(july.balance, 100_000, "入金前は初期残高のまま")
        XCTAssertEqual(august.balance, 300_000, "8月の入金が反映される")
    }

    func test_振替は出金元を減らし振替先を増やす() {
        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: 50_000, date: "2026-08-10",
                                         accountId: bankId, toAccountId: savingsId)))
        store.selectedMonth = Dates.parse("2026-08-15")
        store.reload()

        let bank = store.balanceTrend(accountId: bankId, months: 1).first!
        let savings = store.balanceTrend(accountId: savingsId, months: 1).first!

        XCTAssertEqual(bank.balance, 50_000)
        XCTAssertEqual(savings.balance, 50_000)
    }

    func test_未来の月でも今日までの残高で頭打ちになる() {
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 10_000, date: Dates.today(),
                                         accountId: bankId)))
        // 選択中の月を未来にしても、今日以降の残高は今日時点と同じ
        store.selectedMonth = Dates.shiftMonth(Date(), by: 3)
        store.reload()

        let points = store.balanceTrend(accountId: bankId, months: 2)
        XCTAssertEqual(points.last?.balance, 90_000)
    }
}
