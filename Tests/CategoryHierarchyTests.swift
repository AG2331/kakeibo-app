import XCTest
@testable import Kakeibo

/// 大分類と小分類の扱い。記録は小分類まで、集計は大分類でまとめる。
@MainActor
final class CategoryHierarchyTests: XCTestCase {

    private var tmp: TempDatabase!
    private var store: AppStore!
    private var cashId: Int64!

    override func setUpWithError() throws {
        tmp = try TempDatabase()
        store = AppStore(db: tmp.db, dbPath: tmp.path)
        cashId = store.accountList.first { $0.name == "現金" }!.id!
    }

    override func tearDown() {
        store = nil
        tmp = nil
        super.tearDown()
    }

    private func category(_ name: String, under parent: String? = nil) -> Kakeibo.Category {
        let matches = store.allCategories.filter { $0.name == name }
        guard let parent else {
            return matches.first { $0.parentId == nil }!
        }
        let parentId = store.allCategories.first { $0.name == parent && $0.parentId == nil }!.id!
        return matches.first { $0.parentId == parentId }!
    }

    // MARK: - 既定の小分類

    func test_新規DBに既定の小分類が入る() {
        let food = category("食費")
        let children = store.subcategories(of: food.id!)

        XCTAssertEqual(children.map(\.name), ["食料品", "外食", "カフェ・間食"])
    }

    func test_どの大分類にも小分類が用意されている() {
        for type in [TxType.expense, TxType.income] {
            for parent in store.parentCategories(of: type) {
                XCTAssertFalse(store.subcategories(of: parent.id!).isEmpty,
                               "「\(parent.name)」に小分類が無いと記録できなくなる")
            }
        }
    }

    func test_小分類は親の色を引き継ぐ() {
        let food = category("食費")
        let eatingOut = category("外食", under: "食費")
        XCTAssertEqual(eatingOut.color, food.color)
    }

    func test_自分で作った小分類がある大分類には既定を足さない() throws {
        // v5 相当（小分類なし）から、自作の小分類を1つ持った状態を作る
        let path = try makeTempPath(name: "custom.sqlite")
        let db = try Database(path: path)
        let categories = CategoryRepository(db: db)
        let food = categories.all().first { $0.name == "食費" && $0.parentId == nil }!
        // 既定の小分類をいったん消して、自作のものだけにする
        for child in categories.all().filter({ $0.parentId == food.id }) {
            XCTAssertTrue(categories.delete(id: child.id!))
        }
        XCTAssertTrue(categories.insert(Kakeibo.Category(name: "自炊", type: .expense, parentId: food.id)))
        XCTAssertTrue(db.exec("PRAGMA user_version = 5"))
        db.closeConnection()

        // v6 をもう一度流しても、自作の小分類はそのままで既定は足されない
        let reopened = try Database(path: path)
        let children = CategoryRepository(db: reopened).all().filter { $0.parentId == food.id }
        reopened.closeConnection()

        XCTAssertEqual(children.map(\.name), ["自炊"])
    }

    // MARK: - 大分類の解決

    func test_小分類からは大分類が引ける() {
        let eatingOut = category("外食", under: "食費")
        XCTAssertEqual(store.rootCategory(of: eatingOut.id!)?.name, "食費")
    }

    func test_大分類はそれ自身が返る() {
        let food = category("食費")
        XCTAssertEqual(store.rootCategory(of: food.id!)?.id, food.id)
    }

    // MARK: - 集計は大分類でまとめる

    func test_レポートは小分類を大分類にまとめる() {
        let groceries = category("食料品", under: "食費")
        let eatingOut = category("外食", under: "食費")
        let train = category("電車・バス", under: "交通費")

        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 3_000, date: "2026-09-02",
                                         categoryId: groceries.id, accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_500, date: "2026-09-03",
                                         categoryId: eatingOut.id, accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 800, date: "2026-09-04",
                                         categoryId: train.id, accountId: cashId)))
        store.selectedMonth = Dates.parse("2026-09-15")
        store.reload()

        let slices = store.expenseBreakdown()
        XCTAssertEqual(slices.map(\.category.name), ["食費", "交通費"], "小分類は現れない")
        XCTAssertEqual(slices.first { $0.category.name == "食費" }?.amount, 4_500,
                       "食料品と外食が合算される")
        XCTAssertEqual(slices.first { $0.category.name == "交通費" }?.amount, 800)
    }

    func test_予算は大分類に対して小分類の支出も数える() {
        let groceries = category("食料品", under: "食費")
        let eatingOut = category("外食", under: "食費")
        let food = category("食費")

        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 3_000, date: "2026-09-02",
                                         categoryId: groceries.id, accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_500, date: "2026-09-03",
                                         categoryId: eatingOut.id, accountId: cashId)))
        store.selectedMonth = Dates.parse("2026-09-15")
        store.reload()
        XCTAssertNil(store.setBudget(categoryId: food.id, amount: 20_000))

        let progress = store.budgetProgress().categories.first { $0.name == "食費" }
        XCTAssertEqual(progress?.spent, 4_500, "小分類の支出が大分類の予算に効く")
        XCTAssertEqual(progress?.budget, 20_000)
    }

    func test_大分類のまま記録された過去のデータも集計できる() {
        // 小分類を使う前に記録されたものが混ざっていても壊れない
        let food = category("食費")
        let groceries = category("食料品", under: "食費")
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 2_000, date: "2026-09-02",
                                         categoryId: food.id, accountId: cashId)))
        XCTAssertNil(store.save(TxRecord(type: .expense, amount: 1_000, date: "2026-09-03",
                                         categoryId: groceries.id, accountId: cashId)))
        store.selectedMonth = Dates.parse("2026-09-15")
        store.reload()

        XCTAssertEqual(store.expenseBreakdown().first { $0.category.name == "食費" }?.amount, 3_000)
    }

    // MARK: - 選択肢の並び

    func test_大分類の一覧には小分類が混ざらない() {
        let parents = store.parentCategories(of: .expense)
        XCTAssertTrue(parents.allSatisfy { $0.parentId == nil })
        XCTAssertTrue(parents.contains { $0.name == "食費" })
        XCTAssertFalse(parents.contains { $0.name == "外食" })
    }

    func test_小分類は並び順どおりに返る() {
        let transport = category("交通費")
        XCTAssertEqual(store.subcategories(of: transport.id!).map(\.name),
                       ["電車・バス", "タクシー", "ガソリン"])
    }
}
