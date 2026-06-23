import SwiftUI

/// カテゴリ管理。収入/支出ごとに一覧・追加・編集・削除。
struct CategoryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Category?
    @State private var creatingType: TxType?
    @State private var deleteError = false
    @State private var collapsed: Set<Int64> = []

    var body: some View {
        List {
            ForEach([TxType.expense, TxType.income], id: \.self) { type in
                Section(type.label) {
                    ForEach(store.categories(of: type).filter { $0.parentId == nil }) { parent in
                        parentRow(parent, type: type)

                        if !isCollapsed(parent.id) {
                            ForEach(store.categories(of: type).filter { $0.parentId == parent.id }) { child in
                                Button { editing = child } label: { row(child, depth: 1) }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) { deleteButton(child) }
                            }
                        }
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

    /// 親カテゴリの行。子があれば折りたたみ用のシェブロンを左に表示する。
    private func parentRow(_ category: Category, type: TxType) -> some View {
        let hasChildren = !store.categories(of: type).filter { $0.parentId == category.id }.isEmpty
        return HStack(spacing: 8) {
            if hasChildren {
                Button { toggle(category.id) } label: {
                    Image(systemName: isCollapsed(category.id) ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
            } else {
                Spacer().frame(width: 22)
            }
            Button { editing = category } label: { row(category, depth: 0) }
                .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing) { deleteButton(category) }
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

    private func deleteButton(_ category: Category) -> some View {
        Button(role: .destructive) {
            if !store.deleteCategory(category) { deleteError = true }
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    private func isCollapsed(_ id: Int64?) -> Bool {
        id.map { collapsed.contains($0) } ?? false
    }

    private func toggle(_ id: Int64?) {
        guard let id else { return }
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
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
