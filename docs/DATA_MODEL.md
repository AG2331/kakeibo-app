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
