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
    @Published var creditCardStatements: [Int64: CreditCardStatementInfo] = [:]
    /// 履歴タブのカレンダー用。選択中の月の日別内訳。
    @Published var monthCalendar: [String: DayTotals] = [:]

    init(db: Database, dbPath: String) {
        self.db = db
        self.dbPath = dbPath
        let now = Date()
        self.selectedMonth = Dates.shiftMonth(now, by: 0)
        loadSettings()
        applyDueRecurring()
        reload()
    }

    /// 既定の DB ファイルの場所。
    static func defaultDatabasePath() throws -> String {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return dir.appendingPathComponent("kakeibo.sqlite").path
    }

    /// アプリのドキュメント配下に DB を作って開く。
    /// 開けない場合は投げる（握り潰すと空のデータで起動してしまうため）。
    static func makeDefault() throws -> AppStore {
        let path = try defaultDatabasePath()
        let db = try Database(path: path)
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
        creditCardStatements = Dictionary(uniqueKeysWithValues: accountList
            .filter { $0.hasStatementConfig }
            .compactMap { a in a.id.flatMap { id in creditCardStatement(for: a).map { (id, $0) } } })
        monthCalendar = calendarTotals(of: selectedMonth)
    }

    func shiftMonth(by delta: Int) {
        selectedMonth = Dates.shiftMonth(selectedMonth, by: delta)
        reload()
    }

    // MARK: - 取引

    /// 保存できなければ理由を返す（nil = 成功）。
    @discardableResult
    func save(_ record: TxRecord) -> String? {
        let ok = record.id == nil ? transactions.insert(record) : transactions.update(record)
        guard ok else { return Self.writeFailureMessage }
        reload()
        return nil
    }

    /// 削除できなければ理由を返す（nil = 成功）。
    @discardableResult
    func delete(_ record: TxRecord) -> String? {
        guard let id = record.id else { return "この取引は保存されていません。" }
        guard transactions.delete(id: id) else { return Self.writeFailureMessage }
        reload()
        return nil
    }

    /// 書き込みに失敗したときの共通メッセージ。
    static let writeFailureMessage =
        "保存できませんでした。端末の空き容量を確認して、もう一度お試しください。"

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

    /// 大分類（親カテゴリ）の一覧。
    func parentCategories(of type: TxType) -> [Category] {
        categories(of: type).filter { $0.parentId == nil }
    }

    /// 指定した大分類に属する小分類。
    func subcategories(of parentId: Int64) -> [Category] {
        allCategories.filter { $0.parentId == parentId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 集計に使う大分類。小分類なら親を、親ならそれ自身を返す。
    func rootCategory(of categoryId: Int64) -> Category? {
        guard let category = categoriesById[categoryId] else { return nil }
        guard let parentId = category.parentId else { return category }
        return categoriesById[parentId] ?? category
    }

    /// 保存できなければ理由を返す（nil = 成功）。
    @discardableResult
    func saveCategory(_ category: Category) -> String? {
        let ok: Bool
        if category.id == nil {
            var c = category
            c.sortOrder = (categories(of: category.type).map(\.sortOrder).max() ?? -1) + 1
            ok = categories.insert(c)
        } else {
            ok = categories.update(category)
        }
        guard ok else { return Self.writeFailureMessage }
        reload()
        return nil
    }

    /// 削除できなければ理由を返す（nil = 削除成功）。
    @discardableResult
    func deleteCategory(_ category: Category) -> String? {
        guard let id = category.id else { return "このカテゴリは保存されていません。" }

        let txCount = transactions.countByCategory(id: id)
        if txCount > 0 {
            return "このカテゴリは取引 \(txCount) 件で使われています。先に取引のカテゴリを変更するか、取引を削除してください。"
        }
        let children = categories.childNames(id: id)
        if !children.isEmpty {
            return "このカテゴリにはサブカテゴリ（\(Self.listed(children))）があります。先にサブカテゴリを削除してください。"
        }
        let rules = recurring.usingCategory(id: id)
        if !rules.isEmpty {
            return "このカテゴリは定期取引（\(Self.listed(rules))）で使われています。先に定期取引を変更・削除してください。"
        }
        let budgetMonths = budgets.countByCategory(id: id)
        if budgetMonths > 0 {
            return "このカテゴリには予算が \(budgetMonths) か月分設定されています。先に予算を 0 にしてください。"
        }

        guard categories.delete(id: id) else {
            return "削除できませんでした。他のデータから参照されている可能性があります。"
        }
        reload()
        return nil
    }

    // MARK: - 口座管理

    /// 保存できなければ理由を返す（nil = 成功）。
    @discardableResult
    func saveAccount(_ account: Account) -> String? {
        let ok: Bool
        if account.id == nil {
            var a = account
            a.sortOrder = (accountList.map(\.sortOrder).max() ?? -1) + 1
            ok = accounts.insert(a)
        } else {
            ok = accounts.update(account)
        }
        guard ok else { return Self.writeFailureMessage }
        reload()
        return nil
    }

    /// 削除できなければ理由を返す（nil = 削除成功）。
    @discardableResult
    func deleteAccount(_ account: Account) -> String? {
        guard let id = account.id else { return "この口座は保存されていません。" }

        let txCount = transactions.countByAccount(id: id)
        if txCount > 0 {
            return "この口座は取引 \(txCount) 件で使われています。先に取引の口座を変更するか、取引を削除してください。"
        }
        let children = accounts.childNames(id: id)
        if !children.isEmpty {
            return "この口座には仮想口座（\(Self.listed(children))）があります。先に仮想口座を削除してください。"
        }
        let cards = accounts.paymentSourceOf(id: id)
        if !cards.isEmpty {
            return "この口座は「\(Self.listed(cards))」の引き落とし元に設定されています。先にカード側の設定を変更してください。"
        }
        let rules = recurring.usingAccount(id: id)
        if !rules.isEmpty {
            return "この口座は定期取引（\(Self.listed(rules))）で使われています。先に定期取引を変更・削除してください。"
        }

        guard accounts.delete(id: id) else {
            return "削除できませんでした。他のデータから参照されている可能性があります。"
        }
        reload()
        return nil
    }

    /// 名前の一覧を「A、B ほか2件」の形にまとめる。
    private static func listed(_ names: [String], limit: Int = 2) -> String {
        let head = names.prefix(limit).joined(separator: "、")
        let rest = names.count - min(limit, names.count)
        return rest > 0 ? "\(head) ほか\(rest)件" : head
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

    /// クレジット口座の締め日・支払日設定から、未精算額・請求状況を計算する。
    /// 締め日以降にカード口座へ入った振替を「支払い済み」とみなすため、
    /// 引き落としを記録すると請求額は自動的に消える。
    func creditCardStatement(for account: Account) -> CreditCardStatementInfo? {
        guard account.hasStatementConfig, let id = account.id,
              let closingDay = account.closingDay, let paymentDay = account.paymentDay else { return nil }

        // 直近で締まった請求
        let (start, end) = CreditCardCycle.lastClosedPeriod(closingDay: closingDay)
        let billed = max(0, transactions.netUsage(accountId: id, start: start, end: end))
        let paid = transactions.transferInSum(accountId: id, since: end)
        let due = max(0, billed - paid)
        let dueDate = CreditCardCycle.paymentDate(periodEnd: end, paymentDay: paymentDay,
                                                  monthOffset: account.paymentMonthOffset)

        // まだ締まっていない進行中サイクル
        let (openStart, openEnd) = CreditCardCycle.openPeriod(closingDay: closingDay)
        let upcoming = max(0, transactions.netUsage(accountId: id, start: openStart, end: openEnd))
        let upcomingDue = CreditCardCycle.paymentDate(periodEnd: openEnd, paymentDay: paymentDay,
                                                      monthOffset: account.paymentMonthOffset)

        return CreditCardStatementInfo(
            accountId: id,
            outstandingAmount: max(0, -(accountBalances[id] ?? 0)),
            dueAmount: due,
            dueDate: dueDate,
            isOverdue: due > 0 && dueDate < Dates.today(),
            upcomingAmount: upcoming,
            upcomingDueDate: upcomingDue)
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

    /// カテゴリ別支出。小分類は大分類にまとめて数える（「食料品」「外食」→「食費」）。
    func expenseBreakdown() -> [CategorySlice] {
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        return expenseByRootCategory(start: start, end: end)
            .compactMap { cid, amount in
                categoriesById[cid].map { CategorySlice(category: $0, amount: amount) }
            }
            .sorted { $0.amount > $1.amount }
    }

    /// 期間内の支出を大分類ごとにまとめる。大分類のid -> 金額。
    private func expenseByRootCategory(start: String, end: String) -> [Int64: Int] {
        var result: [Int64: Int] = [:]
        for (categoryId, amount) in transactions.expenseByCategory(start: start, end: end) {
            guard let root = rootCategory(of: categoryId), let rootId = root.id else { continue }
            result[rootId, default: 0] += amount
        }
        return result
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

    /// 日別の収入・支出・振替（カレンダー表示用）。"YYYY-MM-DD" -> 内訳。
    /// カレンダーは暦月で表示するため、月の開始日の設定に関わらず暦月で集計する。
    func calendarTotals(of month: Date) -> [String: DayTotals] {
        let (start, end) = Dates.monthRange(month, startDay: 1)
        var result: [String: DayTotals] = [:]
        for t in transactions.range(start: start, end: end) {
            var totals = result[t.date] ?? DayTotals()
            switch t.type {
            case .income: totals.income += t.amount
            case .expense: totals.expense += t.amount
            case .transfer: totals.transfer += t.amount
            }
            result[t.date] = totals
        }
        return result
    }

    /// 指定日の取引（カレンダーの詳細表示用）。
    func transactions(on day: String) -> [TxRecord] {
        transactions.range(start: day, end: day)
    }

    // MARK: - 口座の詳細

    /// 指定口座に関わる取引（出金元・振替先の両方）。新しい順。
    func transactions(ofAccount id: Int64) -> [TxRecord] {
        transactions.forAccount(id: id)
    }

    /// 口座の残高推移（各月末時点の残高。最後の点は現在の残高）。
    func balanceTrend(accountId: Int64, months: Int = 6) -> [BalancePoint] {
        (0..<months).reversed().map { offset in
            let anchor = Dates.shiftMonth(selectedMonth, by: -offset)
            let (_, end) = Dates.monthRange(anchor, startDay: 1)
            // 未来の月はまだ確定していないので、今日までの残高を使う
            let asOf = min(end, Dates.today())
            return BalancePoint(month: anchor,
                                label: Dates.shortMonthLabel(anchor),
                                balance: accounts.balance(id: accountId, asOf: asOf))
        }
    }

    // MARK: - 予算管理

    /// 当月の予算消化状況。全体予算 + カテゴリ別予算（設定があるもの）。
    func budgetProgress() -> (overall: BudgetProgress?, categories: [BudgetProgress]) {
        let ym = currentYearMonth
        let all = budgets.forMonth(ym)
        let (start, end) = Dates.monthRange(selectedMonth, startDay: settings.monthStartDay)
        // 予算は大分類ごとに立てるので、小分類の支出も親にまとめて数える
        let spentByCat = expenseByRootCategory(start: start, end: end)

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

    /// 保存できなければ理由を返す（nil = 成功）。
    @discardableResult
    func setBudget(categoryId: Int64?, amount: Int) -> String? {
        guard budgets.set(yearMonth: currentYearMonth, categoryId: categoryId,
                          amount: amount) else { return Self.writeFailureMessage }
        objectWillChange.send()
        return nil
    }

    // MARK: - 定期取引

    /// 保存できなければ理由を返す（nil = 成功）。
    @discardableResult
    func saveRecurring(_ rule: RecurringRule) -> String? {
        let ok = rule.id == nil ? recurring.insert(rule) : recurring.update(rule)
        guard ok else { return Self.writeFailureMessage }
        applyDueRecurring()
        reload()
        return nil
    }

    /// 削除できなければ理由を返す（nil = 成功）。
    @discardableResult
    func deleteRecurring(_ rule: RecurringRule) -> String? {
        guard let id = rule.id else { return "この定期取引は保存されていません。" }
        guard recurring.delete(id: id) else { return Self.writeFailureMessage }
        reload()
        return nil
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
        // CSV の標準に合わせて CRLF で区切る（Excel 等での取り込み用）。
        return lines.joined(separator: "\r\n")
    }

    /// CSV を一時ファイルに書き出して URL を返す（共有用）。
    func makeCSVFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakeibo_\(Dates.today()).csv")
        guard let body = exportCSV().data(using: .utf8) else { return nil }
        // BOM を付けないと Excel（日本語環境）で文字化けする。
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(body)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// バックアップ用に DB ファイルの URL を返す。
    var backupFileURL: URL { URL(fileURLWithPath: dbPath) }

    /// 選択した DB ファイルで現在の DB を置き換える。
    /// 検証を通過するまで現在の DB には一切触れず、差し替えに失敗したら元に戻す。
    func restore(from url: URL) -> RestoreResult {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let candidate = fm.temporaryDirectory
            .appendingPathComponent("restore_\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: candidate) }

        // 1. 一時ファイルへ取り込む（ここまでは現在の DB は無傷）
        do {
            try fm.copyItem(at: url, to: candidate)
        } catch {
            return .failed(error.localizedDescription)
        }

        // 2. 中身を検証する。NG ならここで終わり、現在のデータは残る。
        switch Database.inspectBackup(at: candidate.path) {
        case .ok: break
        case .notADatabase: return .invalidFile
        case .notKakeiboBackup: return .notKakeiboBackup
        case .newerSchema: return .newerSchema
        }

        // 3. 検証済みファイルと差し替える。元の DB はロールバック用に退避しておく。
        db.closeConnection()
        let dbURL = URL(fileURLWithPath: dbPath)
        let rollback = fm.temporaryDirectory
            .appendingPathComponent("rollback_\(UUID().uuidString).sqlite")
        var rolledAside = false
        do {
            if fm.fileExists(atPath: dbPath) {
                try fm.moveItem(at: dbURL, to: rollback)
                rolledAside = true
            }
            removeSidecarFiles()
            try fm.copyItem(at: candidate, to: dbURL)
            db = try Database(path: dbPath)   // ここで必要ならマイグレーションも走る
            if rolledAside { try? fm.removeItem(at: rollback) }
            loadSettings()
            reload()
            return .success
        } catch {
            // 差し替えに失敗したら元の DB を書き戻す
            try? fm.removeItem(at: dbURL)
            if rolledAside { try? fm.moveItem(at: rollback, to: dbURL) }
            db = (try? Database(path: dbPath)) ?? db
            loadSettings()
            reload()
            return .failed(error.localizedDescription)
        }
    }

    /// DB 差し替え時に取り残される WAL / ジャーナルを掃除する。
    private func removeSidecarFiles() {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fm.removeItem(atPath: dbPath + suffix)
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
