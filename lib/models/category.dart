/// 取引種別。振替は収支に計上しない。
enum TxType {
  income,
  expense,
  transfer;

  static TxType fromString(String s) =>
      TxType.values.firstWhere((e) => e.name == s, orElse: () => TxType.expense);
}

/// カテゴリ。type は income / expense のみ（transfer はカテゴリを持たない）。
class Category {
  final int? id;
  final String name;
  final TxType type;
  final int? parentId;
  final String? icon;
  final int? color; // ARGB
  final int sortOrder;

  const Category({
    this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.icon,
    this.color,
    this.sortOrder = 0,
  });

  Category copyWith({
    int? id,
    String? name,
    TxType? type,
    int? parentId,
    String? icon,
    int? color,
    int? sortOrder,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.name,
        'parent_id': parentId,
        'icon': icon,
        'color': color,
        'sort_order': sortOrder,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: TxType.fromString(m['type'] as String),
        parentId: m['parent_id'] as int?,
        icon: m['icon'] as String?,
        color: m['color'] as int?,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}
