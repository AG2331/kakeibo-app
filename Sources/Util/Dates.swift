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

    /// その月の初日・末日（YYYY-MM-DD）を返す。
    static func monthRange(_ anchor: Date) -> (start: String, end: String) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: anchor)
        let first = cal.date(from: comps)!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: first)!
        let last = cal.date(byAdding: .day, value: -1, to: nextMonth)!
        return (ymd(first), ymd(last))
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
}
