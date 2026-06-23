# Kakeibo App（家計簿管理アプリ）

iOS（iPhone）向けのオフラインファースト家計簿アプリです。収支の記録・集計・予算管理・レポートまでをローカルで完結させます。

## 技術スタック

| 領域 | 採用技術 | 備考 |
| --- | --- | --- |
| プラットフォーム | iOS 17+ （iPhone） | ネイティブアプリ |
| UI | SwiftUI | |
| 言語 | Swift 5 | |
| ローカルDB | SQLite（`libsqlite3` を直接利用） | オフライン完結・外部依存なし |
| プロジェクト生成 | [XcodeGen](https://github.com/yonomoto/XcodeGen)（`project.yml`） | `.xcodeproj` も同梱 |

## セットアップ・起動

`Kakeibo.xcodeproj` は同梱済みなので、そのまま Xcode で開けます。

```bash
open Kakeibo.xcodeproj
```

Xcode でシミュレータ（または実機）を選び **⌘R** で実行してください。

`project.yml` を変更した場合は再生成します（XcodeGen が必要）:

```bash
brew install xcodegen   # 初回のみ
xcodegen generate
```

## プロジェクト構成

```
Sources/
  KakeiboApp.swift          # @main エントリ
  Models/                   # TxType / Category / Account / TxRecord
  Database/                 # SQLite ラッパ + マイグレーション + 初期データ
  Repositories/             # 取引 / カテゴリ / 口座のCRUD・集計
  Stores/AppStore.swift     # 画面状態（ObservableObject）
  Views/                    # HomeView / TransactionEditView
  Util/                     # Money / Dates / Color+Hex
project.yml                 # XcodeGen 定義
docs/                       # 要件・データモデル・ロードマップ
```

## ドキュメント

- [要件・機能一覧](docs/REQUIREMENTS.md)
- [データモデル設計](docs/DATA_MODEL.md)
- [開発ロードマップ](docs/ROADMAP.md)

## ステータス

✅ MVP（取引CRUD + 当月サマリ + 日付別一覧）動作確認済み（iOS Simulator）
🚧 次フェーズ: カテゴリ/口座/設定の管理画面、グラフ、予算管理
