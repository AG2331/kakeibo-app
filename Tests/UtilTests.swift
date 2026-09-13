import XCTest
@testable import Kakeibo

/// 金額・日付まわりの小さなユーティリティ。
final class UtilTests: XCTestCase {

    // MARK: - 金額

    func test_カンマ付きの入力も整数に戻せる() {
        XCTAssertEqual(Money.parse("1,234"), 1_234)
        XCTAssertEqual(Money.parse("¥1234"), 1_234)
        XCTAssertEqual(Money.parse("1234"), 1_234)
    }

    func test_マイナスの入力を解釈できる() {
        XCTAssertEqual(Money.parse("-5000"), -5_000)
    }

    func test_数字がなければnilを返す() {
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse("-"))
    }

    func test_入力中の金額は3桁区切りで表示される() {
        XCTAssertEqual(AmountField.grouped("1234567"), "1,234,567")
        XCTAssertEqual(AmountField.grouped("1,234"), "1,234")
        XCTAssertEqual(AmountField.grouped(""), "")
        XCTAssertEqual(AmountField.grouped("abc"), "")
    }

    // MARK: - 日付

    func test_暦月の範囲() {
        let range = Dates.monthRange(Dates.parse("2026-09-13"), startDay: 1)
        XCTAssertEqual(range.start, "2026-09-01")
        XCTAssertEqual(range.end, "2026-09-30")
    }

    func test_月の開始日を給料日基準にできる() {
        let range = Dates.monthRange(Dates.parse("2026-09-13"), startDay: 25)
        XCTAssertEqual(range.start, "2026-09-25")
        XCTAssertEqual(range.end, "2026-10-24")
    }

    func test_うるう年の2月は29日まで() {
        let range = Dates.monthRange(Dates.parse("2028-02-10"), startDay: 1)
        XCTAssertEqual(range.end, "2028-02-29")
    }

    func test_定期取引の次回日を頻度ごとに進める() {
        XCTAssertEqual(Dates.advance("2026-09-13", frequency: .daily, interval: 1), "2026-09-14")
        XCTAssertEqual(Dates.advance("2026-09-13", frequency: .weekly, interval: 1), "2026-09-20")
        XCTAssertEqual(Dates.advance("2026-09-13", frequency: .monthly, interval: 1), "2026-10-13")
        XCTAssertEqual(Dates.advance("2026-09-13", frequency: .yearly, interval: 1), "2027-09-13")
    }

    func test_月末の定期取引は短い月に丸められる() {
        XCTAssertEqual(Dates.advance("2026-01-31", frequency: .monthly, interval: 1), "2026-02-28")
    }

    func test_月をずらすと月初を返す() {
        XCTAssertEqual(Dates.ymd(Dates.shiftMonth(Dates.parse("2026-09-13"), by: -1)), "2026-08-01")
        XCTAssertEqual(Dates.ymd(Dates.shiftMonth(Dates.parse("2026-12-13"), by: 1)), "2027-01-01")
    }

    // MARK: - 取引の符号

    func test_収支への寄与は種別で決まる() {
        let income = TxRecord(type: .income, amount: 1_000, date: "2026-09-01", accountId: 1)
        let expense = TxRecord(type: .expense, amount: 1_000, date: "2026-09-01", accountId: 1)
        let transfer = TxRecord(type: .transfer, amount: 1_000, date: "2026-09-01",
                                accountId: 1, toAccountId: 2)

        XCTAssertEqual(income.signedAmount, 1_000)
        XCTAssertEqual(expense.signedAmount, -1_000)
        XCTAssertEqual(transfer.signedAmount, 0, "振替は収支に影響しない")
    }

    // MARK: - 口座の判定

    func test_親口座が設定されていれば仮想口座とみなす() {
        XCTAssertFalse(Account(name: "銀行", type: .bank).isVirtual)
        XCTAssertTrue(Account(name: "貯金用", type: .bank, parentId: 1).isVirtual)
    }

    func test_締め日と支払日が揃ったクレジット口座だけ請求設定ありとみなす() {
        XCTAssertFalse(Account(name: "銀行", type: .bank,
                               closingDay: 15, paymentDay: 10).hasStatementConfig,
                       "クレジット以外は対象外")
        XCTAssertFalse(Account(name: "カード", type: .credit).hasStatementConfig)
        XCTAssertFalse(Account(name: "カード", type: .credit, closingDay: 15).hasStatementConfig)
        XCTAssertTrue(Account(name: "カード", type: .credit,
                              closingDay: 15, paymentDay: 10).hasStatementConfig)
        XCTAssertTrue(Account(name: "カード", type: .credit,
                              closingDay: 0, paymentDay: 0).hasStatementConfig,
                      "0（月末）も設定済みとして扱う")
    }
}
