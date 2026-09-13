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

## テスト

```bash
xcodebuild test -project Kakeibo.xcodeproj -scheme Kakeibo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`Tests/` に 83 件のユニットテストがあります（締め日サイクル、DBの書き込みエラー検知、
バックアップ検証、集計ロジック、削除ガード、復元など）。

## 実機へのビルド・転送

USB か同じ Wi-Fi で iPhone をつないだ状態で:

```bash
./scripts/deploy-iphone.sh                  # 1回だけビルドして転送・起動
./scripts/deploy-iphone.sh --watch          # ソースの変更を検知して毎回転送
./scripts/deploy-iphone.sh --interval 30    # 30分ごとに転送
./scripts/deploy-iphone.sh --list-devices   # 認識しているデバイスを確認
```

署名チーム（Team ID）はプロビジョニングプロファイルから自動検出します。
うまく検出できない場合は `--team <TEAM_ID>` か環境変数 `KAKEIBO_TEAM_ID` で指定してください。
初回は Xcode で一度実機ビルドしておくと確実です。

ビルドログは `.build/logs/` に残ります。常駐させたい場合はスクリプト末尾の
launchd の例を参照してください。

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

## 主な機能

- 取引のCRUD（支出 / 収入 / 振替）、当月サマリ、日付別一覧
- カテゴリ・口座管理、設定（通貨 / テーマ / 月開始日）
- レポート（カテゴリ別円グラフ / 月別推移 / 前月比 / 日別カレンダー、Swift Charts）
- 予算管理（全体・カテゴリ別、消化率バー、超過アラート）
- 定期取引（家賃・給与・サブスク等を予定日に自動計上）
- データ入出力（CSVエクスポート / DBバックアップ・復元）

タブ構成: ホーム / レポート / 予算 / 設定

## ステータス

✅ フェーズ0〜5 完了（iOS Simulator で動作確認済み）
