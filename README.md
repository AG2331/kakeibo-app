# Kakeibo App（家計簿管理アプリ）

スマートフォン向けのオフラインファースト家計簿アプリです。収支の記録・集計・予算管理・レポートまでをローカルで完結させます。

## 技術スタック

| 領域 | 採用技術 | 備考 |
| --- | --- | --- |
| プラットフォーム | iOS / Android（スマホアプリ） | 単一コードベース |
| フレームワーク | Flutter (Dart) | クロスプラットフォーム |
| ローカルDB | SQLite (`sqflite`) | オフライン完結 |
| 状態管理 | Riverpod（予定） | |
| グラフ | `fl_chart`（予定） | カテゴリ別・月別の可視化 |

## ドキュメント

- [要件・機能一覧](docs/REQUIREMENTS.md)
- [データモデル設計](docs/DATA_MODEL.md)
- [開発ロードマップ](docs/ROADMAP.md)

## セットアップ（予定）

```bash
flutter pub get
flutter run
```

## ステータス

🚧 要件定義フェーズ
