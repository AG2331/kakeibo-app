import Foundation

/// クレジットカードの締め日・支払日サイクル計算。
/// day 引数は 1-31 または 0("月末") の規約（Account.closingDay/paymentDay と同じ）。
enum CreditCardCycle {
    /// monthAnchor の月における day に対応する実日付（月末クランプ込み、day<=0は月末）。
    static func resolveDay(_ day: Int, in monthAnchor: Date, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        let monthFirst = calendar.date(from: comps)!
        if day <= 0 {
            let nextMonthFirst = calendar.date(byAdding: .month, value: 1, to: monthFirst)!
            return calendar.date(byAdding: .day, value: -1, to: nextMonthFirst)!
        }
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthFirst)?.count ?? 28
        let offset = min(day, daysInMonth) - 1
        return calendar.date(byAdding: .day, value: offset, to: monthFirst)!
    }

    /// asOf 時点で直近に締めた統計期間 [開始日, 締め日] を YYYY-MM-DD で返す。
    static func lastClosedPeriod(
        closingDay: Int, asOf: Date = Date(), calendar: Calendar = .current
    ) -> (start: String, end: String) {
        let thisMonthClose = resolveDay(closingDay, in: asOf, calendar: calendar)
        let closeDate: Date
        if asOf >= thisMonthClose {
            closeDate = thisMonthClose
        } else {
            let prevMonthAnchor = calendar.date(byAdding: .month, value: -1, to: asOf)!
            closeDate = resolveDay(closingDay, in: prevMonthAnchor, calendar: calendar)
        }
        let prevMonthAnchor = calendar.date(byAdding: .month, value: -1, to: closeDate)!
        let prevClose = resolveDay(closingDay, in: prevMonthAnchor, calendar: calendar)
        let periodStart = calendar.date(byAdding: .day, value: 1, to: prevClose)!
        return (Dates.ymd(periodStart), Dates.ymd(closeDate))
    }

    /// 締め日(periodEnd, YYYY-MM-DD)に対応する支払日（YYYY-MM-DD）を返す。
    static func paymentDate(
        periodEnd: String, paymentDay: Int, monthOffset: Int, calendar: Calendar = .current
    ) -> String {
        let close = Dates.parse(periodEnd)
        let shiftedAnchor = calendar.date(byAdding: .month, value: monthOffset, to: close)!
        return Dates.ymd(resolveDay(paymentDay, in: shiftedAnchor, calendar: calendar))
    }
}
