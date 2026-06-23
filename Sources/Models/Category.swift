import Foundation

/// 取引種別。振替は収支に計上しない。
enum TxType: String, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .income: return "収入"
        case .expense: return "支出"
        case .transfer: return "振替"
        }
    }
}

/// カテゴリ。type は income / expense のみ（transfer はカテゴリを持たない）。
struct Category: Identifiable, Hashable {
    var id: Int64?
    var name: String
    var type: TxType
    var parentId: Int64?
    var icon: String?
    var color: Int?        // ARGB
    var sortOrder: Int

    init(
        id: Int64? = nil,
        name: String,
        type: TxType,
        parentId: Int64? = nil,
        icon: String? = nil,
        color: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.parentId = parentId
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
    }
}
