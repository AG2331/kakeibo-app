import Foundation

/// 日付ユーティリティ。DB保存形式は YYYY-MM-DD 文字列。
enum Dates {
    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f
    }()

    static func ymd(_ date: Date) -> String { ymdFormatter.string(from: date) }

    static func parse(_ s: String) -> Date { ymdFormatter.date(from: s) ?? Date() }

    /// 集計期間の初日・末日（YYYY-MM-DD）を返す。
    /// startDay=1 なら暦月、それ以外は「その月の startDay 日 〜 翌月 startDay 日の前日」。
    static func monthRange(_ anchor: Date, startDay: Int = 1) -> (start: String, end: String) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: anchor)
        let monthFirst = cal.date(from: comps)!

        if startDay <= 1 {
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthFirst)!
            let last = cal.date(byAdding: .day, value: -1, to: nextMonth)!
            return (ymd(monthFirst), ymd(last))
        }

        let startOffset = min(startDay, daysIn(monthFirst, cal)) - 1
        let start = cal.date(byAdding: .day, value: startOffset, to: monthFirst)!

        let nextMonthFirst = cal.date(byAdding: .month, value: 1, to: monthFirst)!
        let nextOffset = min(startDay, daysIn(nextMonthFirst, cal)) - 1
        let nextStart = cal.date(byAdding: .day, value: nextOffset, to: nextMonthFirst)!
        let end = cal.date(byAdding: .day, value: -1, to: nextStart)!
        return (ymd(start), ymd(end))
    }

    private static func daysIn(_ date: Date, _ cal: Calendar) -> Int {
        cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// 月を delta だけずらした月初を返す。
    static func shiftMonth(_ anchor: Date, by delta: Int) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: anchor)
        let first = cal.date(from: comps)!
        return cal.date(byAdding: .month, value: delta, to: first)!
    }

    /// 「6月23日(月)」のような表示用文字列。
    static func displayDate(_ ymdStr: String) -> String {
        displayFormatter.string(from: parse(ymdStr))
    }

    static func yearMonthLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    /// 「6月」のような短い月ラベル。
    static func shortMonthLabel(_ date: Date) -> String {
        "\(Calendar.current.component(.month, from: date))月"
    }
}
