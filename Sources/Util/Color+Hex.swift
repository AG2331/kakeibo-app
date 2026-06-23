import SwiftUI

extension Color {
    /// ARGB 整数（例: 0xFFE57373）から Color を作る。
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// 収入＝緑、支出＝赤の意味的カラー。
enum TxPalette {
    static let income = Color(argb: 0xFF2E7D32)
    static let expense = Color(argb: 0xFFC62828)
    static let transfer = Color(argb: 0xFF607D8B)
    static let accent = Color(argb: 0xFF2E7D32)
}
