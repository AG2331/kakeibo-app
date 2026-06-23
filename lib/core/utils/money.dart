import 'package:intl/intl.dart';

/// 金額は最小通貨単位の整数（円なら1円単位）で保持する。
/// 表示・パースのユーティリティをまとめる。
class Money {
  const Money._();

  static final NumberFormat _yen = NumberFormat.currency(
    locale: 'ja_JP',
    symbol: '¥',
    decimalDigits: 0,
  );

  /// 整数金額を「¥1,234」形式に整形する。
  static String format(int amount) => _yen.format(amount);

  /// 符号付きで整形する（収入は「+」、支出は「-」）。
  static String formatSigned(int amount) {
    if (amount > 0) return '+${format(amount)}';
    return format(amount); // 負値は format 側で「-」が付く
  }

  /// 「1,234」「¥1234」等の入力文字列を整数に変換する。失敗時は null。
  static int? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return null;
    return int.tryParse(cleaned);
  }
}
