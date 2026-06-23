import Foundation

/// 金額は最小通貨単位の整数（円なら1円単位）で保持する。
enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "ja_JP")
        f.maximumFractionDigits = 0
        return f
    }()

    /// 整数金額を「¥1,234」形式に整形する。
    static func format(_ amount: Int) -> String {
        formatter.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }

    /// 「1,234」「¥1234」等の入力文字列を整数に変換する。失敗時は nil。
    static func parse(_ input: String) -> Int? {
        let cleaned = input.filter { $0.isNumber || $0 == "-" }
        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Int(cleaned)
    }
}
