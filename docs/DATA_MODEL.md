# データモデル設計（SQLite）

金額は **整数（最小通貨単位 / 円なら1円）** で保持し、浮動小数点誤差を避ける。
日付は ISO8601 文字列（`YYYY-MM-DD`）、日時は UNIX エポックミリ秒で保持する。

## ER 概要

```
accounts 1 ──< transactions >── 1 categories
                   │
                   └─ to_account_id ─> accounts（振替時）

categories ──< (parent_id) self  （2階層）
budgets >── categories（NULL=全体予算）
recurring_rules >── categories / accounts（テンプレート）
```

## テーブル定義

### accounts（口座・支払い方法）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | INTEGER | PK AUTOINCREMENT | |
| name | TEXT | NOT NULL | 口座名 |
| type | TEXT | NOT NULL | cash / bank / emoney / credit |
| initial_balance | INTEGER | NOT NULL DEFAULT 0 | 初期残高 |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | 並び順 |
| archived | INTEGER | NOT NULL DEFAULT 0 | 0/1 |
| parent_id | INTEGER | FK accounts.id NULL | 仮想口座の場合の親口座（v3） |
| closing_day | INTEGER | NULL | クレカ締め日。1-31、0=月末（typeがcreditの場合のみ意味を持つ、v4） |
| payment_day | INTEGER | NULL | クレカ支払日（引き落とし日）。1-31、0=月末（v4） |
| payment_month_offset | INTEGER | NOT NULL DEFAULT 1 | 締め月から支払月までのオフセット。0=当月/1=翌月/2=翌々月（v4） |
| payment_account_id | INTEGER | FK accounts.id NULL | 引き落とし元口座（v4） |

#### クレジットカード決済の二重計上防止

カード決済は決済したタイミングで `expense`（口座=クレジット口座）として記録し、これを支出計上のタイミングとする。後日の口座引き落としは、二重計上を避けるため `expense` ではなく `transfer`（`account_id`=引き落とし元口座 → `to_account_id`=クレジット口座）として記録する。振替は収支集計（`type IN ('income','expense')` のフィルタ）から常に除外されるため、この運用だけで追加のスキーマなしに二重計上を防げる。クレジット口座の残高はこの結果として「未払い残高（マイナス）」を表す。

`closing_day`/`payment_day`/`payment_month_offset`/`payment_account_id` は、この引き落とし額（直近で締めた期間の支出合計）と次回引き落とし日を自動計算して口座タブに表示するための補助情報であり、会計上の二重計上防止ロジック自体には必須ではない。

### categories（カテゴリ）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | INTEGER | PK AUTOINCREMENT | |
| name | TEXT | NOT NULL | |
| type | TEXT | NOT NULL | income / expense |
| parent_id | INTEGER | FK categories.id NULL | サブカテゴリ用 |
| icon | TEXT | NULL | アイコン識別子 |
| color | INTEGER | NULL | ARGB |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |

### transactions（取引）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | INTEGER | PK AUTOINCREMENT | |
| type | TEXT | NOT NULL | income / expense / transfer |
| amount | INTEGER | NOT NULL | 最小通貨単位、常に正 |
| date | TEXT | NOT NULL | YYYY-MM-DD |
| category_id | INTEGER | FK categories.id NULL | 振替時はNULL |
| account_id | INTEGER | FK accounts.id NOT NULL | 出金/入金元口座 |
| to_account_id | INTEGER | FK accounts.id NULL | 振替先（transfer時） |
| memo | TEXT | NULL | |
| created_at | INTEGER | NOT NULL | epoch ms |

インデックス: `idx_tx_date(date)`, `idx_tx_category(category_id)`, `idx_tx_account(account_id)`。

### budgets（予算）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | INTEGER | PK AUTOINCREMENT | |
| year_month | TEXT | NOT NULL | YYYY-MM |
| category_id | INTEGER | FK categories.id NULL | NULL=全体予算 |
| amount | INTEGER | NOT NULL | |

ユニーク制約: `(year_month, category_id)`。

### recurring_rules（定期取引）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | INTEGER | PK AUTOINCREMENT | |
| type | TEXT | NOT NULL | income / expense / transfer |
| amount | INTEGER | NOT NULL | |
| category_id | INTEGER | FK NULL | |
| account_id | INTEGER | FK NOT NULL | |
| to_account_id | INTEGER | FK NULL | |
| memo | TEXT | NULL | |
| frequency | TEXT | NOT NULL | daily / weekly / monthly / yearly |
| interval | INTEGER | NOT NULL DEFAULT 1 | n回ごと |
| next_date | TEXT | NOT NULL | 次回予定 YYYY-MM-DD |
| end_date | TEXT | NULL | 終了日 |

### settings（設定 / key-value）
| 列 | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| key | TEXT | PK | currency / theme / month_start_day 等 |
| value | TEXT | NOT NULL | |

## マイグレーション方針

- `database.dart` の `onCreate` で v1 スキーマを構築し、デフォルトカテゴリ・現金口座を投入。
- スキーマ変更時は DB バージョンを上げ、`onUpgrade` に差分DDLを追記。
- DDL は `migrations.dart` にバージョン別配列で管理。
