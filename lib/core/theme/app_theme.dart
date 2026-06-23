import 'package:flutter/material.dart';

/// アプリのライト/ダークテーマ。
class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF2E7D32); // 家計＝緑系

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      );

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}

/// 収入＝緑、支出＝赤の意味的カラー。
class TxColors {
  const TxColors._();
  static const income = Color(0xFF2E7D32);
  static const expense = Color(0xFFC62828);
}
