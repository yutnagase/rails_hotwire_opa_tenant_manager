> 🇺🇸 [English version here](rls.md)

# PostgreSQL Row Level Security (RLS)

このドキュメントでは、PostgreSQL の Row Level Security とは何か、マルチテナントアプリケーションにおいてなぜ重要なのか、そして本プロジェクトでどのように実装しているか記載しています。

---

## Row Level Security とは？

Row Level Security (RLS) は、テーブル内でデータベースユーザーがアクセスできる行を制御する機能です。
本プロジェクトではPostgreSQLで構築しています
PostgreSQL仕様での記載の為、他データベースの仕様とは異なる記載となるかもしれませんが、ご了承ください

RLSがない場合、アクセス制御はアプリケーション機能でテーブルレベルで構築します
許可されたユーザーは物理的には、全行を参照できてしまいます。
RLSを使用すると、データベース自体が行レベルのフィルタリングを強制して、ユーザーに割り当てたポリシー内でのレコードのみ、ユーザーに表示します。

| RLS なし | RLS あり |
|---|---|
| 「`tasks` テーブル全行読める」 | 「`tasks` テーブルの自テナントレコードのみ読める」 |
| フィルタリングはアプリケーションコードに依存 | フィルタリングはデータベースエンジンが強制 |

---

## マルチテナントアプリケーションにおけるRLSの重要性

マルチテナントアプリケーションでは、複数の組織（テナント）が同じデータベーステーブルを共有します。一般的なアプローチは、全テーブルに `tenant_id` カラムを追加し、`WHERE tenant_id = ?` でクエリをフィルタリングすることです。
但し、以下の問題点が有ります

問題点: このフィルタリングはアプリケーション層に依存してしまっている。
開発者が `WHERE` 句を忘れたり、スコーピングなしの生SQLを書いたり、クエリビルダーにバグを入れたりすると、他テナントのデータを参照出来てしまい、情報漏洩する可能性があります。

RLS はデータベースレベルのセーフティネットとして機能しますので、上記問題点を解決出来ます

```
アプリケーションバグ → スコープが無いSQLを実行 → RLSが物理的に他テナントのレコードをブロック
```

アプリケーションにバグが有った場合でも、データベースはポリシーに違反するレコードを返さない

---

## 概要

### 1. テーブル単位でRLSを有効化

RLSはデフォルトで無効ですので、テーブルごとに明示的に有効化する必要があります：

```sql
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
```

有効化すると、非スーパーユーザーロールに対してデフォルトで全行が非表示になります
アクセスを許可するポリシーを作成しないとアクセスできません

### 2. ポリシー

ポリシーは、ユーザーがどの行を参照・変更できるかを定義します。
例：

```sql
CREATE POLICY tasks_tenant_isolation ON tasks
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::bigint);
```

ALL（SELECT, INSERT, UPDATE, DELETE）について、`tenant_id` がセッション変数 `app.current_tenant_id` と一致する行のみアクセスを許可する。

### 3. セッション変数

PostgreSQL では `SET` でカスタムセッションレベル変数を設定し、`current_setting()` で読み取ることができます。
本プロジェクトでは `app.current_tenant_id` を使用して、ログイン中ユーザーが所属するテナントのID(`tenant_id`)をアプリケーションからデータベースセッションに渡しています。そうする事で、データベースがRLSポリシーを参照できるようにしています。

### 4. データベースロールと BYPASSRLS

PostgreSQL のスーパーユーザーと `BYPASSRLS` 属性を持つロールは全てのRLSポリシー制御からスキップ出来ます。Railsにおいては管理操作（マイグレーションなど）を行う必要が有ります。設計上の仕様で制限なく実行させなくてはならない為

RLSを有効に機能させるには、通常のリクエスト処理中に `NOBYPASSRLS` のロールを使用する必要があります。

---

## 本プロジェクトでのRLS実装

### アーキテクチャ概要

本プロジェクトでは二層テナント分離戦略を使用：

![二層テナント分離](images/rls_dual_layer.svg)

#### レイヤー1（`acts_as_tenant`）
ActiveRecord のクエリに自動で `WHERE tenant_id = ?` を付加して論理的にテナント管理する。

#### レイヤー2（PostgreSQL RLS）
最後の防衛線としての機能
生のSQLやクエリビルダーのバグで「レイヤー1」を突破されても、データベースレベルで他のテナントレコードを参照出来ない様に、行フィルタリングを行う

### ステップバイステップ

#### ステップ 1: `tenant_id` 付きテーブルの作成

テナント管理されるべき全テーブルに `tenant_id` の外部キーを含める

```ruby
# db/migrate/*_create_projects.rb
create_table :projects do |t|
  t.references :tenant, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
end
```

同様に 他のテーブル(`users`, `tasks` テーブルなど)にも適用

#### ステップ 2: RLS 制限付きデータベースへロールを追加

`NOSUPERUSER` と `NOBYPASSRLS` を持つ専用ロール `rails_user` を作成。
これらのポリシーが割り当てられたユーザーは、RLS ポリシーの影響下となる

```ruby
# db/migrate/*_create_rls_role.rb
execute <<~SQL
  CREATE ROLE rails_user WITH LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
SQL
```

このロールに全テーブルとシーケンスへの標準 CRUD 権限を付与する

```ruby
execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rails_user;"
execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rails_user;"
```

#### ステップ 3: RLS の有効化とポリシーの作成

テナント管理されるべき全テーブルに対して RLS を有効化し、各テーブルにポリシーを追加

```ruby
# db/migrate/*_enable_rls_policies.rb
%w[users projects tasks].each do |table|
  execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;"
  execute <<~SQL
    CREATE POLICY #{table}_tenant_isolation ON #{table}
      FOR ALL
      USING (tenant_id = current_setting('app.current_tenant_id')::bigint);
  SQL
end
```

`tenants` テーブルは Rails仕様で`tenant_id` ではなく `id` カラムに対してポリシーの作成

```sql
CREATE POLICY tenants_isolation ON tenants
  FOR ALL
  USING (id = current_setting('app.current_tenant_id')::bigint);
```

RLS 対象外のテーブルとして以下存在する（Rails マイグレーション関連）
`schema_migrations` 
`ar_internal_metadata`

#### ステップ 4: リクエストごとのロール切り替え

アプリケーションはデフォルトで `postgres`（スーパーユーザー）として PostgreSQL に接続するが、共通Controllerクラスにてリクエスト受付時に `around_action` が制限付きロールに切り替えを行う

```ruby
# app/controllers/application_controller.rb
def scope_to_tenant
  tenant = Tenant.find_by!(subdomain: request.subdomain)
  set_current_tenant(tenant)

  conn = ActiveRecord::Base.connection
  conn.execute("SET ROLE rails_user")                          # 制限付きロールに切り替え
  conn.execute("SET app.current_tenant_id = '#{tenant.id}'")  # テナントコンテキストを設定

  yield
ensure
  conn = ActiveRecord::Base.connection
  conn.execute("RESET ROLE")                  # スーパーユーザーに復元
  conn.execute("RESET app.current_tenant_id") # テナントコンテキストをクリア
end
```

`ensure` ブロックにて、リクエスト受付時にエラーが発生した場合、
接続が必ずスーパーユーザーロールに復元される仕組みとする

### データベースユーザー(postgres, rails_user)の使い分け

| ユーザー | 用途 | RLS の動作 |
|---|---|---|
| `postgres` (スーパーユーザー) | マイグレーション、スキーマ変更、DB 接続デフォルト | RLS影響外 |
| `rails_user` | アプリケーションリクエスト処理 | RLS影響下 |

単一コネクションプール（`postgres`）で動的に `SET ROLE` を行い、セットアップを可能とする
また、以下の特徴を持たせる
- `postgres`にて、フル権限でマイグレーションを実行できる
- アプリケーションへのリクエスト受付時、RLS影響下の`rails_user`で実行する事で、RLSによる制限を持たせられる

### 各ステップでの詳細

ロール切り替えからクエリ実行、接続クリーンアップまでの単一リクエストのステップは以下図を参照のこと

![リクエストごとの RLS 有効化フロー](images/rls_per_request.svg)

### 多層防御: 各レイヤーの詳細

| シナリオ | acts_as_tenant のみ | RLS あり |
|---|---|---|
| 通常の ActiveRecord クエリ | ✅ 安全 | ✅ 安全 |
| テナントスコープなしの生 SQL | ❌ データ漏洩 | ✅ データ漏洩をブロック |
| クエリビルダー / スコープのバグ | ❌ データ漏洩 | ✅ データ漏洩をブロック |
| 直接 DB コンソールアクセス (`rails_user` として) | ❌ 保護なし | ✅ データ漏洩をブロック |

---

## まとめ

| 概念 | 本プロジェクトでの実装 |
|---|---|
| RLS 制限ロール | `rails_user` (`NOBYPASSRLS`) |
| テナント用セッション変数 | `app.current_tenant_id` |
| ポリシー条件 | `tenant_id = current_setting('app.current_tenant_id')::bigint` |
| ロール切り替え | `around_action` 内の `SET ROLE` / `RESET ROLE` |
| マイグレーションの安全性 | `postgres`（スーパーユーザー）として実行、RLS をバイパス |
| RLS 対象テーブル | `tenants`, `users`, `projects`, `tasks` |
| RLS 対象外テーブル | `schema_migrations`, `ar_internal_metadata` |
