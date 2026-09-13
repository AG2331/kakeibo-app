import Foundation

struct SettingsRepository {
    let db: Database

    func get(_ key: String) -> String? {
        db.query("SELECT value FROM settings WHERE key = ?", [.text(key)])
            .first?.string("value")
    }

    @discardableResult
    func set(_ key: String, _ value: String) -> Bool {
        db.run("INSERT INTO settings(key, value) VALUES(?,?) " +
               "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
               [.text(key), .text(value)]).ok
    }

    /// 保存済みの設定をまとめて読み込む（未設定はデフォルト）。
    func load() -> AppSettings {
        let currency = get("currency").flatMap(Currency.init) ?? .jpy
        let theme = get("theme").flatMap(ThemeMode.init) ?? .system
        let day = get("month_start_day").flatMap(Int.init) ?? 1
        return AppSettings(currency: currency, theme: theme,
                           monthStartDay: min(max(day, 1), 28))
    }
}
