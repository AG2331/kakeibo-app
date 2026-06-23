import 'package:intl/intl.dart';

final DateFormat _ymd = DateFormat('yyyy-MM-dd');
final DateFormat _ym = DateFormat('yyyy-MM');

/// 日付ユーティリティ。DB保存形式は YYYY-MM-DD 文字列。
class Dates {
  const Dates._();

  static String ymd(DateTime d) => _ymd.format(d);
  static String ym(DateTime d) => _ym.format(d);
  static DateTime parse(String s) => _ymd.parseStrict(s);

  /// その月の初日・末日（YYYY-MM-DD）を返す。
  static (String start, String end) monthRange(DateTime anchor) {
    final start = DateTime(anchor.year, anchor.month, 1);
    final end = DateTime(anchor.year, anchor.month + 1, 0);
    return (ymd(start), ymd(end));
  }

  /// 「6月23日(月)」のような表示用文字列。
  static String displayDate(String ymdStr) {
    final d = parse(ymdStr);
    return DateFormat('M月d日(E)', 'ja_JP').format(d);
  }
}
