import SwiftUI

/// カテゴリ管理。収入/支出ごとに一覧・追加・編集・削除。
struct CategoryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Category?
    @State private var creatingType: TxType?
    @State private var deleteError = false

    var body: some View {
        List {
            ForEach([TxType.expense, TxType.income], id: \.self) { type in
                Section(type.label) {
                    ForEach(store.orderedCategories(of: type), id: \.category.id) { entry in
                        Button { editing = entry.category } label: {
                            row(entry.category, depth: entry.depth)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        delete(offsets, type: type)
                    }

                    Button {
                        creatingType = type
                    } label: {
                        Label("\(type.label)カテゴリを追加", systemImage: "plus.circle")
                    }
                }
            }
        }
        .navigationTitle("カテゴリ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { category in
            CategoryEditView(existing: category, type: category.type)
        }
        .sheet(item: $creatingType) { type in
            CategoryEditView(existing: nil, type: type)
        }
        .alert("削除できません", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このカテゴリは取引で使われているか、サブカテゴリを持っています。先にそれらを変更・削除してください。")
        }
    }

    private func row(_ category: Category, depth: Int) -> some View {
        HStack(spacing: 12) {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Circle()
                .fill(category.color.map { Color(argb: $0) } ?? .gray)
                .frame(width: depth > 0 ? 16 : 20, height: depth > 0 ? 16 : 20)
            Text(category.name)
                .font(depth > 0 ? .callout : .body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, depth > 0 ? 12 : 0)
    }

    private func delete(_ offsets: IndexSet, type: TxType) {
        let list = store.orderedCategories(of: type)
        for index in offsets {
            if !store.deleteCategory(list[index].category) {
                deleteError = true
            }
        }
    }
}

/// カテゴリの追加・編集。
struct CategoryEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: Category?
    let type: TxType

    @State private var name: String
    @State private var color: Int
    @State private var parentId: Int64?

    /// 選択肢の色パレット（ARGB）。
    private let palette: [Int] = [
        0xFFE57373, 0xFFF06292, 0xFFBA68C8, 0xFF9575CD, 0xFF7986CB,
        0xFF64B5F6, 0xFF4FC3F7, 0xFF4DB6AC, 0xFF81C784, 0xFFAED581,
        0xFFFFB74D, 0xFFFF8A65, 0xFFA1887F, 0xFF90A4AE, 0xFF66BB6A,
    ]

    init(existing: Category?, type: TxType) {
        self.existing = existing
        self.type = type
        _name = State(initialValue: existing?.name ?? "")
        _color = State(initialValue: existing?.color ?? 0xFF90A4AE)
        _parentId = State(initialValue: existing?.parentId)
    }

    /// 親候補（同種別の親カテゴリのみ。自分自身は除く）。サブカテゴリを持つ親は従属不可。
    private var parentOptions: [Category] {
        let hasChildren = existing?.id.map { store.categories.childCount(id: $0) > 0 } ?? false
        return hasChildren ? [] : store.parentCategoryCandidates(type: type, excluding: existing?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("カテゴリ名", text: $name)
                }
                if !parentOptions.isEmpty {
                    Section {
                        Picker("所属（サブカテゴリにする）", selection: $parentId) {
                            Text("親カテゴリ（独立）").tag(Int64?.none)
                            ForEach(parentOptions) { Text("\($0.name) の中").tag(Int64?.some($0.id ?? 0)) }
                        }
                    } footer: {
                        Text("親カテゴリを選ぶと、その配下のサブカテゴリ（例: 食費 > 外食）になります。")
                    }
                }
                Section("色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(palette, id: \.self) { argb in
                            Circle()
                                .fill(Color(argb: argb))
                                .frame(height: 34)
                                .overlay {
                                    if argb == color {
                                        Image(systemName: "checkmark")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { color = argb }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(existing == nil ? "\(type.label)カテゴリを追加" : "カテゴリを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = Category(
            id: existing?.id,
            name: trimmed,
            type: type,
            parentId: parentId,
            icon: existing?.icon,
            color: color,
            sortOrder: existing?.sortOrder ?? 0
        )
        store.saveCategory(category)
        dismiss()
    }
}
