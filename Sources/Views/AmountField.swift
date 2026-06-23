import SwiftUI

/// 金額入力フィールド。テンキー（数字のみ）で、入力中も3桁ごとに「,」区切りで表示する。
/// バインド先の文字列にはカンマ付きの表示文字列が入るが、保存時は Money.parse が
/// 数字以外を除去するためそのまま整数化できる。
struct AmountField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { Self.grouped(text) },
            set: { text = Self.grouped($0) }
        ))
        .keyboardType(.numberPad)
    }

    /// 文字列から数字だけを取り出し、3桁区切りに整形する。空なら空文字。
    static func grouped(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard let n = Int(digits) else { return "" }
        return formatter.string(from: NSNumber(value: n)) ?? digits
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()
}
