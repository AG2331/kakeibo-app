import XCTest
@testable import Kakeibo

/// 締め日・支払日サイクルの計算。月末や短い月のクランプが主な関心事。
final class CreditCardCycleTests: XCTestCase {

    // MARK: - 直近で締めた期間

    func test_締め日を過ぎていれば当月の締め日で区切る() {
        let period = CreditCardCycle.lastClosedPeriod(
            closingDay: 15, asOf: Dates.parse("2026-09-20"), calendar: testCalendar)
        XCTAssertEqual(period.start, "2026-08-16")
        XCTAssertEqual(period.end, "2026-09-15")
    }

    func test_締め日前なら前月の締め日で区切る() {
        let period = CreditCardCycle.lastClosedPeriod(
            closingDay: 15, asOf: Dates.parse("2026-09-05"), calendar: testCalendar)
        XCTAssertEqual(period.start, "2026-07-16")
        XCTAssertEqual(period.end, "2026-08-15")
    }

    func test_締め日当日は締め済みとして扱う() {
        let period = CreditCardCycle.lastClosedPeriod(
            closingDay: 15, asOf: Dates.parse("2026-09-15"), calendar: testCalendar)
        XCTAssertEqual(period.end, "2026-09-15")
    }

    func test_月末締めは月の最終日で区切る() {
        let period = CreditCardCycle.lastClosedPeriod(
            closingDay: 0, asOf: Dates.parse("2026-02-20"), calendar: testCalendar)
        XCTAssertEqual(period.start, "2026-01-01")
        XCTAssertEqual(period.end, "2026-01-31")
    }

    // MARK: - 進行中の期間

    func test_進行中の期間は直近の締め日の翌日から次の締め日まで() {
        let open = CreditCardCycle.openPeriod(
            closingDay: 15, asOf: Dates.parse("2026-09-13"), calendar: testCalendar)
        XCTAssertEqual(open.start, "2026-08-16")
        XCTAssertEqual(open.end, "2026-09-15")
    }

    func test_進行中の期間は締め済みの期間と重ならない() {
        let asOf = Dates.parse("2026-09-13")
        let closed = CreditCardCycle.lastClosedPeriod(closingDay: 15, asOf: asOf, calendar: testCalendar)
        let open = CreditCardCycle.openPeriod(closingDay: 15, asOf: asOf, calendar: testCalendar)
        XCTAssertLessThan(closed.end, open.start, "締め済みの終わりより後から進行中が始まること")
    }

    func test_月末締めの進行中期間はうるう年でない2月に収まる() {
        let open = CreditCardCycle.openPeriod(
            closingDay: 0, asOf: Dates.parse("2026-02-20"), calendar: testCalendar)
        XCTAssertEqual(open.start, "2026-02-01")
        XCTAssertEqual(open.end, "2026-02-28")
    }

    // MARK: - 支払日

    func test_翌月払いの支払日() {
        let due = CreditCardCycle.paymentDate(
            periodEnd: "2026-09-15", paymentDay: 27, monthOffset: 1, calendar: testCalendar)
        XCTAssertEqual(due, "2026-10-27")
    }

    func test_翌々月払いの支払日() {
        let due = CreditCardCycle.paymentDate(
            periodEnd: "2026-09-15", paymentDay: 10, monthOffset: 2, calendar: testCalendar)
        XCTAssertEqual(due, "2026-11-10")
    }

    func test_支払日31日は短い月の末日に丸める() {
        let due = CreditCardCycle.paymentDate(
            periodEnd: "2026-01-31", paymentDay: 31, monthOffset: 1, calendar: testCalendar)
        XCTAssertEqual(due, "2026-02-28", "2月は28日までなので丸められること")
    }

    func test_月末指定の支払日は月の最終日になる() {
        let due = CreditCardCycle.paymentDate(
            periodEnd: "2026-08-31", paymentDay: 0, monthOffset: 1, calendar: testCalendar)
        XCTAssertEqual(due, "2026-09-30")
    }

    // MARK: - 日付の解決

    func test_31日指定はうるう年でない2月に丸められる() {
        let resolved = CreditCardCycle.resolveDay(
            31, in: Dates.parse("2026-02-10"), calendar: testCalendar)
        XCTAssertEqual(Dates.ymd(resolved), "2026-02-28")
    }

    func test_31日指定はうるう年の2月29日になる() {
        let resolved = CreditCardCycle.resolveDay(
            31, in: Dates.parse("2028-02-10"), calendar: testCalendar)
        XCTAssertEqual(Dates.ymd(resolved), "2028-02-29")
    }

    func test_0指定は月末を意味する() {
        let resolved = CreditCardCycle.resolveDay(
            0, in: Dates.parse("2026-04-10"), calendar: testCalendar)
        XCTAssertEqual(Dates.ymd(resolved), "2026-04-30")
    }
}
