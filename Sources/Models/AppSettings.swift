import SwiftUI

/// 表示テーマ。
enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "システムに従う"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }

    /// SwiftUI に渡す配色。system は nil（OS設定に従う）。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 通貨。金額は整数（最小単位ではなく主要単位の整数）として扱う簡易対応。
enum Currency: String, CaseIterable, Identifiable {
    case jpy = "JPY"
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .jpy: return "¥"
        case .usd: return "$"
        case .eur: return "€"
        }
    }

    var localeId: String {
        switch self {
        case .jpy: return "ja_JP"
        case .usd: return "en_US"
        case .eur: return "de_DE"
        }
    }

    var label: String {
        switch self {
        case .jpy: return "円 (JPY)"
        case .usd: return "ドル (USD)"
        case .eur: return "ユーロ (EUR)"
        }
    }
}

/// アプリ設定のまとまり。
struct AppSettings {
    var currency: Currency
    var theme: ThemeMode
    var monthStartDay: Int   // 1〜28

    static let `default` = AppSettings(currency: .jpy, theme: .system, monthStartDay: 1)
}
