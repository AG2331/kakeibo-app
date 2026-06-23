import Foundation

/// 金額は整数で保持する。表示通貨は設定に応じて切り替える。
enum Money {
    /// 現在の表示通貨。AppStore が設定読込時にセットする。
    static var currency: Currency = .jpy {
        didSet { cache.removeAll() }
    }

    private static var cache: [Currency: NumberFormatter] = [:]

    private static func formatter(for c: Currency) -> NumberFormatter {
        if let f = cache[c] { return f }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: c.localeId)
        f.currencySymbol = c.symbol
        f.maximumFractionDigits = 0   // 整数（主要単位）として扱う
        cache[c] = f
        return f
    }

    /// 整数金額を現在通貨で「¥1,234」形式に整形する。
    static func format(_ amount: Int) -> String {
        formatter(for: currency).string(from: NSNumber(value: amount))
            ?? "\(currency.symbol)\(amount)"
    }

    /// 「1,234」「¥1234」等の入力文字列を整数に変換する。失敗時は nil。
    static func parse(_ input: String) -> Int? {
        let cleaned = input.filter { $0.isNumber || $0 == "-" }
        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Int(cleaned)
    }
}
