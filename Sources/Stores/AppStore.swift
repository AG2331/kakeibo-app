import Foundation
import SwiftUI

/// アプリ全体の状態とDBアクセスを束ねる。
@MainActor
final class AppStore: ObservableObject {
    private(set) var db: Database
    let dbPath: String

    // リポジトリは DB を差し替え（復元）できるよう計算プロパティにする。
    var transactions: TransactionRepository { TransactionRepository(db: db) }
    var categories: CategoryRepository { CategoryRepository(db: db) }
    var accounts: AccountRepository { AccountRepository(db: db) }
    var settingsRepo: SettingsRepository { SettingsRepository(db: db) }
    var budgets: BudgetRepository { BudgetRepository(db: db) }
    var recurring: RecurringRepository { RecurringRepository(db: db) }

    @Published var selectedMonth: Date
    @Published var monthTransactions: [TxRecord] = []
    @Published var summary: MonthlySummary = .empty
    @Published var categoriesById: [Int64: Category] = [:]
    @Published var allCategories: [Category] = []
    @Published var accountList: [Account] = []
    @Published var accountBalances: [Int64: Int] = [:]
    @Published var settings: AppSettings = .default
    @Published var recurringRules: [RecurringRule] = []

    init(db: Database, dbPath: String) {
        self.db = db
        self.dbPath = dbPath
        let now = Date()
        self.selectedMonth = Dates.shiftMonth(now, by: 0)
        loadSettings()
        applyDueRecurring()
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
        return AppStore(db: db, dbPath: path)
    }

    /// 集計の対象 year-month（YYYY-MM）。
    var currentYearMonth: String { Dates.ym(selectedMonth) }

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
        recurringRules = recurring.all()
    }

    func shiftMonth(by delta: Int) {
        selectedMonth = Dates.shiftMonth(selectedMonth, by: delta)
        reload()
    }

    // MARK: - 取引

    func save(_ record: TxRecord) {
        if record.id == nil { transactions.insert(record) } else { transactions.update(record) }
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

    /// 親カテゴリ→その配下のサブカテゴリの順に並べる（depth: 0=親, 1=サブ）。
    func orderedCategories(of type: TxType) -> [(category: Category, depth: Int)] {
        let all = categories(of: type)
        var result: [(Category, Int)] = []
        for parent in all where parent.parentId == nil {
            result.append((parent, 0))
            for child in all where child.parentId == parent.id {
                result.append((child, 1))
            }
        }
        return result
    }

    /// サブカテゴリの親候補（同じ種別の親カテゴリのみ。自分自身は除く）。
    func parentCategoryCandidates(type: TxType, excluding selfId: Int64?) -> [Category] {
        categories(of: type).filter { $0.parentId == nil && $0.id != selfId }
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

    @discardableResult
    func deleteCategory(_ category: Category) -> Bool {
        guard let id = category.id else { return false }
        if transactions.countByCategory(id: id) > 0 { return false }
        if categories.childCount(id: id) > 0 { return false } // サブカテゴリを持つ親は削除不可
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
        if accounts.childCount(id: id) > 0 { return false } // 仮想口座を持つ親は削除不可
        accounts.delete(id: id)
        reload()
        return true
    }

    /// 取引登録用に、親口座→その仮想口座の順で並べた口座リスト（depth: 0=親, 1=仮想）。
    var orderedAccounts: [(account: Account, depth: Int)] {
        var result: [(Account, Int)] = []
        for top in accountList where top.parentId == nil {
            result.append((top, 0))
            for kid in accountList where kid.parentId == top.id {
                result.append((kid, 1))
            }
        }
        return result
    }

    /// 親口座になれる候補（独立口座のみ。自分自身は除く）。
    func parentCandidates(excluding selfId: Int64?) -> [Account] {
        accountList.filter { $0.parentId == nil && $0.id != selfId }
    }

    /// 総額タブ用: 口座の階層別残高と総資産。
    func accountOverview() -> (grandTotal: Int, nodes: [AccountNode]) {
        let nodes: [AccountNode] = accountList
            .filter { $0.parentId == nil }
            .map { top in
                let own = top.id.flatMap { accountBalances[$0] } ?? 0
                let kids = accountList
                    .filter { $0.parentId == top.id }
                    .map { (account: $0, balance: $0.id.flatMap { accountBalances[$0] } ?? 0) }
                return AccountNode(account: top, ownBalance: own, children: kids)
            }
        let grand = nodes.reduce(0) { $0 + $1.total }
        return (grand, nodes)
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

    func expenseBreakdown() -> [CategorySlice] {
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        let map = transactions.expenseByCategory(start: start, end: end)
        return map.compactMap { cid, amount in
            categoriesById[cid].map { CategorySlice(category: $0, amount: amount) }
        }
        .sorted { $0.amount > $1.amount }
    }

    func monthlyTrend(months: Int = 6) -> [MonthBar] {
        (0..<months).reversed().map { offset in
            let anchor = Dates.shiftMonth(selectedMonth, by: -offset)
            let (start, end) = Dates.monthRange(anchor, startDay: settings.monthStartDay)
            let s = transactions.summary(start: start, end: end)
            return MonthBar(month: anchor, label: Dates.shortMonthLabel(anchor),
                            income: s.income, expense: s.expense)
        }
    }

    func previousSummary() -> MonthlySummary {
        let anchor = Dates.shiftMonth(selectedMonth, by: -1)
        let (start, end) = Dates.monthRange(anchor, startDay: settings.monthStartDay)
        return transactions.summary(start: start, end: end)
    }

    /// 日別の支出合計（カレンダー表示用）。"YYYY-MM-DD" -> 支出額。
    func dailyExpense() -> [String: Int] {
        var result: [String: Int] = [:]
        for t in monthTransactions where t.type == .expense {
            result[t.date, default: 0] += t.amount
        }
        return result
    }

    // MARK: - 予算管理

    /// 当月の予算消化状況。全体予算 + カテゴリ別予算（設定があるもの）。
    func budgetProgress() -> (overall: BudgetProgress?, categories: [BudgetProgress]) {
        let ym = currentYearMonth
        let all = budgets.forMonth(ym)
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        let spentByCat = transactions.expenseByCategory(start: start, end: end)

        let overall = all.first { $0.categoryId == nil }.map {
            BudgetProgress(categoryId: nil, name: "全体", color: nil,
                           budget: $0.amount, spent: summary.expense)
        }

        let categoryProgress: [BudgetProgress] = all
            .filter { $0.categoryId != nil }
            .compactMap { b in
                guard let cid = b.categoryId, let cat = categoriesById[cid] else { return nil }
                return BudgetProgress(categoryId: cid, name: cat.name, color: cat.color,
                                      budget: b.amount, spent: spentByCat[cid] ?? 0)
            }
            .sorted { $0.ratio > $1.ratio }

        return (overall, categoryProgress)
    }

    func budgetAmount(categoryId: Int64?) -> Int {
        budgets.forMonth(currentYearMonth)
            .first { $0.categoryId == categoryId }?.amount ?? 0
    }

    func setBudget(categoryId: Int64?, amount: Int) {
        budgets.set(yearMonth: currentYearMonth, categoryId: categoryId, amount: amount)
        objectWillChange.send()
    }

    // MARK: - 定期取引

    func saveRecurring(_ rule: RecurringRule) {
        if rule.id == nil { recurring.insert(rule) } else { recurring.update(rule) }
        applyDueRecurring()
        reload()
    }

    func deleteRecurring(_ rule: RecurringRule) {
        guard let id = rule.id else { return }
        recurring.delete(id: id)
        reload()
    }

    /// next_date が今日以前のルールから取引を生成し、next_date を進める。
    func applyDueRecurring() {
        let today = Dates.today()
        for rule in recurring.all() {
            guard let id = rule.id else { continue }
            var next = rule.nextDate
            var generated = false
            while next <= today {
                if let end = rule.endDate, next > end { break }
                transactions.insert(TxRecord(
                    type: rule.type, amount: rule.amount, date: next,
                    categoryId: rule.categoryId, accountId: rule.accountId,
                    toAccountId: rule.toAccountId, memo: rule.memo))
                next = Dates.advance(next, frequency: rule.frequency, interval: rule.interval)
                generated = true
            }
            if generated { recurring.updateNextDate(id: id, next) }
        }
    }

    // MARK: - データ入出力

    /// 全取引を CSV 文字列にする。
    func exportCSV() -> String {
        var lines = ["日付,種別,金額,カテゴリ,口座,振替先,メモ"]
        let accountName = Dictionary(uniqueKeysWithValues: accountList.compactMap { a in
            a.id.map { ($0, a.name) }
        })
        let rows = transactions.range().sorted { $0.date < $1.date }
        for t in rows {
            let cat = t.categoryId.flatMap { categoriesById[$0]?.name } ?? ""
            let acc = accountName[t.accountId] ?? ""
            let toAcc = t.toAccountId.flatMap { accountName[$0] } ?? ""
            let cols = [t.date, t.type.label, String(t.amount), cat, acc, toAcc, t.memo ?? ""]
            lines.append(cols.map(Self.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// CSV を一時ファイルに書き出して URL を返す（共有用）。
    func makeCSVFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakeibo_\(Dates.today()).csv")
        do {
            try exportCSV().data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// バックアップ用に DB ファイルの URL を返す。
    var backupFileURL: URL { URL(fileURLWithPath: dbPath) }

    /// 選択した DB ファイルで現在の DB を置き換える。
    @discardableResult
    func restore(from url: URL) -> Bool {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        db.closeConnection()
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dbPath) { try fm.removeItem(atPath: dbPath) }
            try fm.copyItem(at: url, to: URL(fileURLWithPath: dbPath))
            db = try Database(path: dbPath)
            loadSettings()
            reload()
            return true
        } catch {
            // 失敗時は元の場所で開き直す
            db = (try? Database(path: dbPath)) ?? db
            return false
        }
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
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
