import Foundation
import SwiftUI

/// アプリ全体の状態とDBアクセスを束ねる。
@MainActor
final class AppStore: ObservableObject {
    let db: Database
    let transactions: TransactionRepository
    let categories: CategoryRepository
    let accounts: AccountRepository
    let settingsRepo: SettingsRepository

    @Published var selectedMonth: Date
    @Published var monthTransactions: [TxRecord] = []
    @Published var summary: MonthlySummary = .empty
    @Published var categoriesById: [Int64: Category] = [:]
    @Published var allCategories: [Category] = []
    @Published var accountList: [Account] = []
    @Published var accountBalances: [Int64: Int] = [:]
    @Published var settings: AppSettings = .default

    init(db: Database) {
        self.db = db
        self.transactions = TransactionRepository(db: db)
        self.categories = CategoryRepository(db: db)
        self.accounts = AccountRepository(db: db)
        self.settingsRepo = SettingsRepository(db: db)
        let now = Date()
        self.selectedMonth = Dates.shiftMonth(now, by: 0)
        loadSettings()
        reload()
    }

    /// アプリのドキュメント配下に DB を作って開く。
    static func makeDefault() -> AppStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("kakeibo.sqlite").path
        // swiftlint:disable:next force_try
        let db = try! Database(path: path)
        return AppStore(db: db)
    }

    // MARK: - 読み込み

    func loadSettings() {
        settings = settingsRepo.load()
        Money.currency = settings.currency
    }

    func reload() {
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        summary = transactions.summary(start: start, end: end)
        monthTransactions = transactions.range(start: start, end: end)
        let cats = categories.all()
        allCategories = cats
        categoriesById = Dictionary(uniqueKeysWithValues: cats.compactMap { c in
            c.id.map { ($0, c) }
        })
        accountList = accounts.all()
        accountBalances = Dictionary(uniqueKeysWithValues: accountList.compactMap { a in
            a.id.map { ($0, accounts.balance(id: $0)) }
        })
    }

    func shiftMonth(by delta: Int) {
        selectedMonth = Dates.shiftMonth(selectedMonth, by: delta)
        reload()
    }

    // MARK: - 取引

    func save(_ record: TxRecord) {
        if record.id == nil {
            transactions.insert(record)
        } else {
            transactions.update(record)
        }
        reload()
    }

    func delete(_ record: TxRecord) {
        guard let id = record.id else { return }
        transactions.delete(id: id)
        reload()
    }

    // MARK: - カテゴリ管理

    func categories(of type: TxType) -> [Category] {
        allCategories.filter { $0.type == type }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func saveCategory(_ category: Category) {
        if category.id == nil {
            var c = category
            c.sortOrder = (categories(of: category.type).map(\.sortOrder).max() ?? -1) + 1
            categories.insert(c)
        } else {
            categories.update(category)
        }
        reload()
    }

    /// 使用中（取引から参照）なら false を返し、削除しない。
    @discardableResult
    func deleteCategory(_ category: Category) -> Bool {
        guard let id = category.id else { return false }
        if transactions.countByCategory(id: id) > 0 { return false }
        categories.delete(id: id)
        reload()
        return true
    }

    // MARK: - 口座管理

    func saveAccount(_ account: Account) {
        if account.id == nil {
            var a = account
            a.sortOrder = (accountList.map(\.sortOrder).max() ?? -1) + 1
            accounts.insert(a)
        } else {
            accounts.update(account)
        }
        reload()
    }

    @discardableResult
    func deleteAccount(_ account: Account) -> Bool {
        guard let id = account.id else { return false }
        if transactions.countByAccount(id: id) > 0 { return false }
        accounts.delete(id: id)
        reload()
        return true
    }

    // MARK: - 設定

    func setCurrency(_ currency: Currency) {
        settingsRepo.set("currency", currency.rawValue)
        settings.currency = currency
        Money.currency = currency
        objectWillChange.send()
    }

    func setTheme(_ theme: ThemeMode) {
        settingsRepo.set("theme", theme.rawValue)
        settings.theme = theme
    }

    func setMonthStartDay(_ day: Int) {
        let clamped = min(max(day, 1), 28)
        settingsRepo.set("month_start_day", String(clamped))
        settings.monthStartDay = clamped
        reload()
    }

    // MARK: - 集計・レポート

    /// 選択中の期間のカテゴリ別支出（多い順）。
    func expenseBreakdown() -> [CategorySlice] {
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        let map = transactions.expenseByCategory(start: start, end: end)
        return map.compactMap { cid, amount in
            categoriesById[cid].map { CategorySlice(category: $0, amount: amount) }
        }
        .sorted { $0.amount > $1.amount }
    }

    /// 直近 months か月分の月別収支（古い→新しい順）。
    func monthlyTrend(months: Int = 6) -> [MonthBar] {
        (0..<months).reversed().map { offset in
            let anchor = Dates.shiftMonth(selectedMonth, by: -offset)
            let (start, end) = Dates.monthRange(anchor, startDay: settings.monthStartDay)
            let s = transactions.summary(start: start, end: end)
            return MonthBar(month: anchor, label: Dates.shortMonthLabel(anchor),
                            income: s.income, expense: s.expense)
        }
    }

    /// 前期間（1つ前の月）のサマリ。前月比の算出に使う。
    func previousSummary() -> MonthlySummary {
        let anchor = Dates.shiftMonth(selectedMonth, by: -1)
        let (start, end) = Dates.monthRange(anchor, startDay: settings.monthStartDay)
        return transactions.summary(start: start, end: end)
    }

    /// 取引の日付ごとグルーピング（date DESC を保ったまま）。
    var groupedByDate: [(date: String, items: [TxRecord])] {
        var order: [String] = []
        var map: [String: [TxRecord]] = [:]
        for t in monthTransactions {
            if map[t.date] == nil { order.append(t.date) }
            map[t.date, default: []].append(t)
        }
        return order.map { ($0, map[$0]!) }
    }
}
