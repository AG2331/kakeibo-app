import Foundation

struct CategoryRepository {
    let db: Database

    func all(type: TxType? = nil) -> [Category] {
        let rows: [Row]
        if let type {
            rows = db.query(
                "SELECT * FROM categories WHERE type = ? ORDER BY sort_order ASC, id ASC",
                [.text(type.rawValue)])
        } else {
            rows = db.query("SELECT * FROM categories ORDER BY sort_order ASC, id ASC")
        }
        return rows.map(Self.map)
    }

    @discardableResult
    func insert(_ c: Category) -> Int64 {
        db.run(
            "INSERT INTO categories(name, type, parent_id, icon, color, sort_order) VALUES(?,?,?,?,?,?)",
            [.text(c.name), .text(c.type.rawValue), SQLValue(c.parentId),
             SQLValue(c.icon), SQLValue(c.color), .int(Int64(c.sortOrder))])
    }

    func update(_ c: Category) {
        guard let id = c.id else { return }
        db.run(
            "UPDATE categories SET name=?, type=?, parent_id=?, icon=?, color=?, sort_order=? WHERE id=?",
            [.text(c.name), .text(c.type.rawValue), SQLValue(c.parentId),
             SQLValue(c.icon), SQLValue(c.color), .int(Int64(c.sortOrder)), .int(id)])
    }

    func delete(id: Int64) {
        db.run("DELETE FROM categories WHERE id=?", [.int(id)])
    }

    /// 指定カテゴリの子（サブカテゴリ）数。
    func childCount(id: Int64) -> Int {
        db.query("SELECT COUNT(*) AS c FROM categories WHERE parent_id=?", [.int(id)])
            .first?.int("c") ?? 0
    }

    static func map(_ r: Row) -> Category {
        Category(
            id: r.int64("id"),
            name: r.string("name") ?? "",
            type: TxType(rawValue: r.string("type") ?? "expense") ?? .expense,
            parentId: r.int64("parent_id"),
            icon: r.string("icon"),
            color: r.int("color"),
            sortOrder: r.int("sort_order") ?? 0
        )
    }
}
