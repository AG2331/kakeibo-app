import SwiftUI

/// カテゴリを「大分類 → 小分類」の2段で選ぶ。
/// 例: 食費 を選んでから 食料品 / 外食 を選ぶ。
/// selection には最終的に選ばれたカテゴリ（小分類があればそれ）が入る。
struct CategoryPickerField: View {
    @EnvironmentObject private var store: AppStore

    let type: TxType
    @Binding var selection: Int64?

    /// 表示用の大分類。selection から導けるが、小分類を選ぶ前の状態も保つ必要がある。
    @State private var parentId: Int64?

    var body: some View {
        Picker("大分類", selection: $parentId) {
            Text("選択してください").tag(Int64?.none)
            ForEach(store.parentCategories(of: type)) { category in
                Text(category.name).tag(Int64?.some(category.id ?? 0))
            }
        }
        .onAppear { syncParentFromSelection() }
        .onChange(of: selection) { _, _ in syncParentFromSelection() }
        .onChange(of: parentId) { _, newValue in applyParentChange(newValue) }
        .onChange(of: type) { _, _ in parentId = nil }

        if let parentId {
            let children = store.subcategories(of: parentId)
            if children.isEmpty {
                LabeledContent("小分類") {
                    Text("なし").foregroundStyle(.secondary)
                }
            } else {
                Picker("小分類", selection: $selection) {
                    Text("選択してください").tag(Int64?.none)
                    ForEach(children) { category in
                        Text(category.name).tag(Int64?.some(category.id ?? 0))
                    }
                }
            }
        }
    }

    /// 保存される値から、表示用の大分類を合わせる（編集で開いたときなど）。
    private func syncParentFromSelection() {
        guard let selection, let category = store.categoriesById[selection] else { return }
        let root = category.parentId ?? category.id
        if parentId != root { parentId = root }
    }

    /// 大分類を選び直したときに、小分類の選択をどうするか決める。
    private func applyParentChange(_ newParent: Int64?) {
        guard let newParent else {
            selection = nil
            return
        }
        // すでにその大分類に属するものが選ばれているなら触らない
        if let selection, let category = store.categoriesById[selection],
           (category.parentId ?? category.id) == newParent {
            return
        }
        let children = store.subcategories(of: newParent)
        switch children.count {
        case 0:  selection = newParent        // 小分類が無ければ大分類のまま記録する
        case 1:  selection = children[0].id   // ひとつだけなら選ぶ手間を省く
        default: selection = nil              // 選んでもらう
        }
    }
}
