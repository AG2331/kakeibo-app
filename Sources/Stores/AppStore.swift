import Foundation
import SwiftUI

/// アプリ全体の状態とDBアクセスを束ねる。
@MainActor
final class AppStore: ObservableObject {
    let db: Database
    let transactions: TransactionRepository
    let categories: CategoryRepository
    let accounts: AccountRepository

    @Published var selectedMonth: Date
    @Published var monthTransactions: [TxRecord] = []
    @Published var summary: MonthlySummary = .empty
    @Published var categoriesById: [Int64: Category] = [:]
    @Published var accountList: [Account] = []

    init(db: Database) {
        self.db = db
        self.transactions = TransactionRepository(db: db)
        self.categories = CategoryRepository(db: db)
        self.accounts = AccountRepository(db: db)
        let now = Date()
        self.selectedMonth = Dates.shiftMonth(now, by: 0)
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

    func reload() {
        let (start, end) = Dates.monthRange(selectedMonth)
        summary = transactions.summary(start: start, end: end)
        monthTransactions = transactions.range(start: start, end: end)
        let cats = categories.all()
        categoriesById = Dictionary(uniqueKeysWithValues: cats.compactMap { c in
            c.id.map { ($0, c) }
        })
        accountList = accounts.all()
    }

    func shiftMonth(by delta: Int) {
        selectedMonth = Dates.shiftMonth(selectedMonth, by: delta)
        reload()
    }

    // MARK: - 取引の更新

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
