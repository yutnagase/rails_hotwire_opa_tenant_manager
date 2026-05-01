> 🇺🇸 [English version here](rls.md)

# PostgreSQL Row Level Security(RLS)

PostgreSQLのRow Level Securityとは何か、マルチテナントアプリケーションにおいてなぜ重要なのか、本プロジェクトでどのように実装しているかについて記載する。

---

## Row Level Securityとは

Row Level Security(RLS)は、テーブル内でデータベースユーザーがアクセスできる行を制御するPostgreSQLの機能である。
本プロジェクトはPostgreSQLで構築しているため、以下はPostgreSQL前提の記載となる。他のデータベースでは仕様が異なる可能性がある点はご了承いただきたい。

RLSがない場合、アクセス制御はアプリケーション側でテーブルレベルで構築することになる。
許可されたユーザーは物理的には全行を参照できてしまう。
RLSを使用すると、データベース自体が行レベルのフィルタリングを強制するため、ポリシーに合致するレコードのみがユーザーに表示される。

| RLSなし | RLSあり |
|---|---|
| 「`tasks`テーブルの全行が読める」 | 「`tasks`テーブルの自テナントのレコードのみ読める」 |
| フィルタリングはアプリケーションコードに依存 | フィルタリングはデータベースエンジンが強制 |

---

## マルチテナントアプリケーションにおけるRLSの重要性

マルチテナントアプリケーションでは、複数の組織（テナント）が同じデータベーステーブルを共有する。一般的なアプローチは全テーブルに`tenant_id`カラムを追加し、`WHERE tenant_id = ?`でクエリをフィルタリングすることである。

ただし、以下の問題点がある。

このフィルタリングはアプリケーション層に依存してしまっている、という点である。
開発者が`WHERE`句を付け忘れたり、スコーピングなしの生SQLを書いたり、クエリビルダーにバグを入れたりすると、他テナントのデータが参照可能となり、情報漏洩につながる可能性がある。

RLSはデータベースレベルのセーフティネットとして機能するため、この問題を解決できる。

```
アプリケーションのバグ → スコープなしのSQLを実行 → RLSが物理的に他テナントのレコードをブロック
```

アプリケーションにバグがあったとしても、データベースはポリシーに違反するレコードを返さない。

---

## 基本的な仕組み

### 1. テーブル単位でRLSを有効化

RLSはデフォルトで無効のため、テーブルごとに明示的に有効化する必要がある。

```sql
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
```

有効化すると、非スーパーユーザーロールに対してデフォルトで全行が非表示となる。
アクセスを許可するポリシーを作成しなければ何も参照できない。

### 2. ポリシー

ポリシーにより、ユーザーがどの行を参照・変更できるかを定義する。

```sql
CREATE POLICY tasks_tenant_isolation ON tasks
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::bigint);
```

ALL（SELECT, INSERT, UPDATE, DELETE）について、`tenant_id`がセッション変数`app.current_tenant_id`と一致する行のみアクセスを許可する。

### 3. セッション変数

PostgreSQLでは`SET`でカスタムのセッションレベル変数を設定し、`current_setting()`で読み取ることができる。
本プロジェクトでは`app.current_tenant_id`を使用して、ログイン中ユーザーの所属テナントIDをアプリケーションからデータベースセッションに渡している。これによりデータベースがRLSポリシーを参照できるようになる。

### 4. データベースロールとBYPASSRLS

PostgreSQLのスーパーユーザーや`BYPASSRLS`属性を持つロールはRLSポリシーを素通りできる。Railsではマイグレーションなどの管理操作で制限なく実行する必要があるため、これが必要となる。

RLSを有効に機能させるには、通常のリクエスト処理中は`NOBYPASSRLS`のロールを使用しなければならない。

---

## 本プロジェクトでの実装

### アーキテクチャ概要

二層のテナント分離戦略を採用している。

![二層テナント分離](images/rls_dual_layer.svg)

#### レイヤー1（acts_as_tenant）
ActiveRecordのクエリに自動で`WHERE tenant_id = ?`を付加し、論理的にテナント管理を行う。

#### レイヤー2（PostgreSQL RLS）
最後の防衛線としての機能を担う。
生SQLやクエリビルダーのバグでレイヤー1を突破されても、データベースレベルで他テナントのレコードを参照できないよう行フィルタリングを行う。

### ステップバイステップ

#### ステップ1: tenant_id付きテーブルの作成

テナント管理が必要な全テーブルに`tenant_id`の外部キーを含める。

```ruby
# db/migrate/*_create_projects.rb
create_table :projects do |t|
  t.references :tenant, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
end
```

`users`, `tasks`テーブルなどにも同様に適用する。

#### ステップ2: RLS制限付きロールの作成

`NOSUPERUSER`と`NOBYPASSRLS`を持つ専用ロール`rails_user`を作成する。
このロールに割り当てられたユーザーはRLSポリシーの影響下に置かれる。

```ruby
# db/migrate/*_create_rls_role.rb
execute <<~SQL
  CREATE ROLE rails_user WITH LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
SQL
```

全テーブルとシーケンスへの標準CRUD権限を付与する。

```ruby
execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rails_user;"
execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rails_user;"
```

#### ステップ3: RLSの有効化とポリシー作成

テナント管理対象の全テーブルでRLSを有効化し、各テーブルにポリシーを追加する。

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

`tenants`テーブルはRails仕様で`tenant_id`ではなく`id`カラムに対してポリシーを作成する。

```sql
CREATE POLICY tenants_isolation ON tenants
  FOR ALL
  USING (id = current_setting('app.current_tenant_id')::bigint);
```

RLS対象外のテーブル（Railsマイグレーション関連）
- `schema_migrations`
- `ar_internal_metadata`

#### ステップ4: リクエストごとのロール切り替え

アプリケーションはデフォルトで`postgres`（スーパーユーザー）としてPostgreSQLに接続するが、`ApplicationController`の`around_action`でリクエスト処理中だけ制限付きロールに切り替える。

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

`ensure`ブロックにより、リクエスト処理中にエラーが発生した場合でも接続は必ずスーパーユーザーロールに復元される。

### データベースユーザー(postgres, rails_user)の使い分け

| ユーザー | 用途 | RLSの動作 |
|---|---|---|
| `postgres`(スーパーユーザー) | マイグレーション、スキーマ変更、DB接続デフォルト | RLS影響外 |
| `rails_user` | アプリケーションのリクエスト処理 | RLS影響下 |

単一コネクションプール（`postgres`）で`SET ROLE`を動的に行うことで、以下を両立させている。
- `postgres`でフル権限のマイグレーションを実行できる
- リクエスト処理時は`rails_user`でRLSの制限を受ける

### リクエストごとのRLS有効化フロー

ロール切り替えからクエリ実行、接続クリーンアップまでの流れは以下の図を参照のこと。

![リクエストごとのRLS有効化フロー](images/rls_per_request.svg)

### 多層防御: 各レイヤーの比較

| シナリオ | acts_as_tenantのみ | RLSあり |
|---|---|---|
| 通常のActiveRecordクエリ | 安全 | 安全 |
| テナントスコープなしの生SQL | データ漏洩 | ブロック |
| クエリビルダー / スコープのバグ | データ漏洩 | ブロック |
| 直接DBコンソールアクセス(`rails_user`として) | 保護なし | ブロック |

---

## まとめ

| 概念 | 本プロジェクトでの実装 |
|---|---|
| RLS制限ロール | `rails_user`(`NOBYPASSRLS`) |
| テナント用セッション変数 | `app.current_tenant_id` |
| ポリシー条件 | `tenant_id = current_setting('app.current_tenant_id')::bigint` |
| ロール切り替え | `around_action`内の`SET ROLE` / `RESET ROLE` |
| マイグレーションの安全性 | `postgres`（スーパーユーザー）で実行し、RLSをバイパス |
| RLS対象テーブル | `tenants`, `users`, `projects`, `tasks` |
| RLS対象外テーブル | `schema_migrations`, `ar_internal_metadata` |
