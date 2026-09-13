import XCTest
@testable import Kakeibo

/// 履歴タブのカレンダー用の集計。
@MainActor
final class CalendarTests: XCTestCase {

    private var tmp: TempDatabase!
    private var store: AppStore!
    private var cashId: Int64!
    private var bankId: Int64!

    override func setUpWithError() throws {
        tmp = try TempDatabase()
        store = AppStore(db: tmp.db, dbPath: tmp.path)
        cashId = store.accountList.first { $0.name == "現金" }!.id!
        XCTAssertNil(store.saveAccount(Account(name: "銀行", type: .bank, initialBalance: 100_000)))
        bankId = store.accountList.first { $0.name == "銀行" }!.id!
    }

    override func tearDown() {
        store = nil
        tmp = nil
        super.tearDown()
    }

    private func seedMonth() {
        let food = store.allCategories.first { $0.name == "食費" }?.id
        let salary = store.allCategories.first { $0.name == "給与" }?.id
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_200, date: "2026-09-02",
                                         categoryId: food, accountId: cashId, memo: "コンビニ")))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 800, date: "2026-09-02",
                                         categoryId: food, accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .income, amount: 280_000, date: "2026-09-10",
                                         categoryId: salary, accountId: bankId)))
        XCTAssertNil(store.save(TxRecord(type: .transfer, amount: 50_000, date: "2026-09-10",
                                         accountId: bankId, toAccountId: cashId)))
        store.selectedMonth = Dates.parse("2026-09-15")
        store.reload()
    }

    func test_日ごとに収入支出振替を分けて集計する() {
        seedMonth()
        let totals = store.calendarTotals(of: Dates.parse("2026-09-15"))

        XCTAssertEqual(totals["2026-09-02"]?.expense, 2_000, "同じ日の支出は合算される")
        XCTAssertEqual(totals["2026-09-02"]?.income, 0)
        XCTAssertEqual(totals["2026-09-10"]?.income, 280_000)
        XCTAssertEqual(totals["2026-09-10"]?.transfer, 50_000, "振替も記録として現れる")
        XCTAssertEqual(totals["2026-09-10"]?.expense, 0)
    }

    func test_記録のない日は含まれない() {
        seedMonth()
        let totals = store.calendarTotals(of: Dates.parse("2026-09-15"))
        XCTAssertNil(totals["2026-09-03"])
    }

    func test_他の月の記録は混ざらない() {
        seedMonth()
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 5_000, date: "2026-08-31",
                                         accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 7_000, date: "2026-10-01",
                                         accountId: cashId)))

        let totals = store.calendarTotals(of: Dates.parse("2026-09-15"))
        XCTAssertNil(totals["2026-08-31"])
        XCTAssertNil(totals["2026-10-01"])
    }

    func test_月の開始日の設定に関わらず暦月で集計する() {
        seedMonth()
        store.setMonthStartDay(25)   // 給料日基準にしても

        let totals = store.calendarTotals(of: Dates.parse("2026-09-15"))
        XCTAssertNotNil(totals["2026-09-02"], "暦月の初めの記録もカレンダーに出ること")
        XCTAssertNotNil(totals["2026-09-10"])
    }

    func test_選択した日の取引を新しい順に取り出せる() {
        seedMonth()
        let items = store.transactions(on: "2026-09-02")

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.date == "2026-09-02" })
        XCTAssertTrue(items.contains { $0.memo == "コンビニ" })
    }

    func test_記録のない日を選んでも空で返る() {
        seedMonth()
        XCTAssertTrue(store.transactions(on: "2026-09-03").isEmpty)
    }

    func test_月を切り替えるとカレンダーの集計も入れ替わる() {
        seedMonth()
        XCTAssertFalse(store.monthCalendar.isEmpty)

        store.shiftMonth(by: 1)   // 2026-10 へ
        XCTAssertTrue(store.monthCalendar.isEmpty, "10月には記録がない")

        store.shiftMonth(by: -1)
        XCTAssertEqual(store.monthCalendar["2026-09-10"]?.income, 280_000)
    }

    func test_記録を直すとカレンダーの集計も追従する() {
        seedMonth()
        let target = store.transactions(on: "2026-09-02").first { $0.memo == "コンビニ" }!

        var edited = target
        edited.amount = 3_000
        XCTAssertNil(store.save(edited))

        XCTAssertEqual(store.monthCalendar["2026-09-02"]?.expense, 3_800, "1,200 が 3,000 に変わる")
    }

    func test_記録を消すとカレンダーの集計から外れる() {
        seedMonth()
        let target = store.transactions(on: "2026-09-10").first { $0.type == .transfer }!

        XCTAssertNil(store.delete(target))

        XCTAssertEqual(store.monthCalendar["2026-09-10"]?.transfer, 0)
        XCTAssertEqual(store.monthCalendar["2026-09-10"]?.income, 280_000, "収入は残る")
    }

    func test_1日分の内訳は収支と振替を区別する() {
        var totals = DayTotals()
        totals.income = 1_000
        totals.expense = 400
        totals.transfer = 5_000

        XCTAssertEqual(totals.net, 600, "振替は収支に含めない")
        XCTAssertFalse(totals.isEmpty)
        XCTAssertTrue(DayTotals().isEmpty)
    }
}
