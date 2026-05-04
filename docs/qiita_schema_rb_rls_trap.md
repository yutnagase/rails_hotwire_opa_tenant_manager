# Railsのschema.rbは「execute」を無視する：RLSで詰んだ話

## はじめに

Rails 8.1 + PostgreSQL 17 で、マルチテナント対応のタスク管理アプリを開発している。テナント間のデータ分離にはPostgreSQLのRow Level Security（RLS）を採用し、マイグレーションファイル内で `execute` を使ってRLSポリシーやロールを定義していた。

開発環境はDevContainer（Docker Compose）で構築しており、PostgreSQL、OPA（Open Policy Agent）、Railsアプリの3コンテナ構成。

リポジトリ: https://github.com/yutnagase/rails_hotwire_opa_tenant_manager

ある日、DevContainerを再作成して `db:create` → `db:migrate` → `db:seed` を実行し、ブラウザでアクセスしたところ、画面が真っ白で何も表示されない。ターミナルにもエラーは出ない。ここから調査が始まった。

## 環境

| 項目           | バージョン / 構成               |
| -------------- | ------------------------------- |
| Ruby           | 3.4                             |
| Rails          | 8.1                             |
| PostgreSQL     | 17（RLS有効）                   |
| 開発環境       | DevContainer（Docker Compose）  |
| 認証           | Devise + omniauth-auth0         |
| 認可           | Open Policy Agent（OPA）        |
| マルチテナント | acts_as_tenant + PostgreSQL RLS |

## 症状：ブラウザで何も表示されない

Railsサーバーを起動し、`http://company-a.localhost:8080/` にアクセスしても反応がない。
ターミナル上のPumaのログにもリクエストが記録されていない。

まず、DevContainer内からcurlで直接アクセスを試みた。サブドメインベースのテナント識別を使っているため、`Host` ヘッダーを明示的に指定する。

```bash
curl -v -H "Host: company-a.localhost" http://localhost:8080/ > /tmp/response_body.txt 2> /tmp/response_headers.txt
```

レスポンスヘッダーを確認すると、HTTPステータスは500。

```
< HTTP/1.1 500 Internal Server Error
```

レスポンスボディにはRailsのエラー画面がHTMLで返っていた。

```html
<h2>
  PG::InvalidParameterValue: ERROR: role &quot;rails_user&quot; does not exist
</h2>
```

`rails_user` というPostgreSQLロールが存在しないことが原因だった。

## 背景：RLSとrails_userロールの設計

このアプリでは、RLSによるテナント分離のために以下の設計を採用している。

- DBへの接続は `postgres`（スーパーユーザー / BYPASSRLS）で行う
- リクエスト処理時に `around_action` 内で `SET ROLE rails_user` に切り替える
- `rails_user` は `NOSUPERUSER / NOBYPASSRLS` なので、RLSポリシーが適用される
- リクエスト終了時に `RESET ROLE` でスーパーユーザーに戻す

`rails_user` ロールの作成は、マイグレーションファイル `20260426025740_create_rls_role.rb` で行う設計だった。

```ruby
class CreateRlsRole < ActiveRecord::Migration[8.1]
  def up
    role = ENV.fetch("RLS_ROLE", "rails_user")
    role_pw = ENV.fetch("RLS_ROLE_PASSWORD", "rails_password")

    execute <<~SQL
      DO $$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{role}') THEN
          CREATE ROLE #{role} WITH LOGIN PASSWORD '#{role_pw}' NOSUPERUSER NOBYPASSRLS;
        END IF;
      END $$;
    SQL

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role};"
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{role};"
  end

  def down
    role = ENV.fetch("RLS_ROLE", "rails_user")
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM #{role};"
    execute "REASSIGN OWNED BY #{role} TO postgres;"
    execute "DROP OWNED BY #{role};"
    execute "DROP ROLE IF EXISTS #{role};"
  end
end
```

## 調査：マイグレーションは「実行済み」なのにロールがない

マイグレーションのステータスを確認すると、全て `up` になっている。

```bash
$ bin/rails db:migrate:status

 Status   Migration ID    Migration Name
--------------------------------------------------
   up     20260426025717  Create tenants
   up     20260426025726  Create users
   up     20260426025732  Create projects
   up     20260426025739  Create tasks
   up     20260426025740  Create rls role
   up     20260426025741  Enable rls policies
   up     20260428120000  Add seed admin to users
```

しかし、PostgreSQLに直接接続してロール一覧を確認すると、`rails_user` は存在しない。

```bash
$ psql -U postgres -h db -c "\du"
                             List of roles
 Role name |                         Attributes
-----------+------------------------------------------------------------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS
```

マイグレーションは `up` なのにロールがない。矛盾している。

## 仮説と検証：マイグレーションSQL自体に問題があるのか

まず、マイグレーション内のSQLに問題がないか確認するため、`CREATE ROLE` を直接実行してみた。

```bash
$ psql -U postgres -h db -c "CREATE ROLE rails_user WITH LOGIN PASSWORD 'rails_password' NOSUPERUSER NOBYPASSRLS;"
CREATE ROLE

$ psql -U postgres -h db -c "\du"
                              List of roles
 Role name  |                         Attributes
------------+------------------------------------------------------------
 postgres   | Superuser, Create role, Create DB, Replication, Bypass RLS
 rails_user |
```

問題なく作成できる。SQL自体に誤りはない。

次に、ロールを削除した上で `schema_migrations` からレコードを消し、マイグレーションを強制的に再実行してみた。

```bash
$ psql -U postgres -h db -c "DROP ROLE rails_user;"
$ psql -U postgres -h db -d tenant_manager_development \
    -c "DELETE FROM schema_migrations WHERE version = '20260426025740';"
$ bin/rails db:migrate:up VERSION=20260426025740
== 20260426025740 CreateRlsRole: migrating ====================================
-- execute("DO $$ BEGIN\n  IF NOT EXISTS ...")
   -> 0.0655s
-- execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES ...")
   -> 0.0045s
...
== 20260426025740 CreateRlsRole: migrated (0.0800s) ===========================
```

マイグレーションが実行され、ロールも作成された。マイグレーションファイルのコード自体には問題がないことが確定した。

## 核心：db:migrate の出力が空

ここで改めて、クリーンな状態からの `db:create` → `db:migrate` の出力を見返す。

```bash
$ bin/rails db:create
Created database 'tenant_manager_development'
Created database 'tenant_manager_test'
$ bin/rails db:migrate
$
```

`db:migrate` の出力が完全に空である。通常、マイグレーションが実行されれば `== 20260426025717 CreateTenants: migrating ===` のようなログが表示されるはずだ。何も出ていないということは、マイグレーションが1つも実行されていない。

にもかかわらず `db:migrate:status` では全て `up` になっている。これはどういうことか。

通常、`db:migrate` が何もせずに終わるのは、`schema_migrations` テーブルに全バージョンが登録済みで、Railsが「DBは最新状態」と判断している場合である。この状態は以下の経路で発生しうる。

- `schema.rb` のロード
- `structure.sql` のロード
- 手動で `schema_migrations` にバージョンをINSERT

今回は `schema.rb` のロードによってこの状態が作られていた。

## 根本原因：schema.rb の自動ロード

答えは `db/schema.rb` にあった。

Railsのデフォルト設定（`config.active_record.schema_format = :ruby`）では、`db:migrate` 実行後に `db/schema.rb` が自動生成される。このファイルにはActiveRecord DSLで表現されたテーブル定義が含まれる。

```ruby
ActiveRecord::Schema[8.1].define(version: 2026_04_28_120000) do
  enable_extension "pg_catalog.plpgsql"

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "tenant_id", null: false
    # ...
  end

  create_table "tasks", force: :cascade do |t|
    # ...
  end

  # ...
end
```

ここに `CREATE ROLE`、`GRANT`、`ENABLE ROW LEVEL SECURITY`、`CREATE POLICY` は一切含まれていない。`schema.rb` はActiveRecord DSLで表現できるものしか保持しないからだ。

なお、`db:create` はデータベースを作成するだけで、`schema.rb` のロードは行わない。実際に `db:create` 直後にDBを確認すると、`schema_migrations` テーブルすら存在しなかった。

```bash
$ bin/rails db:create
Created database 'tenant_manager_development'

$ psql -U postgres -h db -d tenant_manager_development -c "SELECT * FROM schema_migrations;"
ERROR:  relation "schema_migrations" does not exist
```

`schema.rb`（または `structure.sql`）をロードしているのは `db:migrate` の処理フローの中である。Rails 8.1 では、`db:migrate` 自体が明示的に `schema.rb` をロードするわけではない。しかし、空のデータベースに対してはRailsが「未初期化状態」と判断し、マイグレーションを順に実行する代わりに、スキーマファイル（`schema.rb` / `structure.sql`）をロードしてデータベースを最新状態に揃える最適化が行われる。この時、テーブルが作成されると同時に `schema_migrations` テーブルにも全マイグレーションのバージョンが記録される。

この挙動はRailsの内部最適化によるものであり、`db:migrate` が常にマイグレーションファイルを実行するとは限らない点に注意が必要である。

その結果、マイグレーションファイルは1つも実行されない。`execute` で書いた `CREATE ROLE` も `ENABLE ROW LEVEL SECURITY` も、一度も実行されないまま `up` と表示される。

## 今回はまった原因

結論から言うと、RLSを使う時点で `schema.rb` は破綻する。RLSの導入に必要な以下の操作は、全てActiveRecord DSLで表現できない。

- `ENABLE ROW LEVEL SECURITY`
- `CREATE POLICY`
- `CREATE ROLE`
- `GRANT`

これらは全て `execute` で生SQLを書くしかなく、`schema.rb` には一切反映されない。つまり、RLSをマイグレーションで管理しようとした時点で、`schema_format = :sql` への切り替えは必須だった。

一方、通常のCRUD系Railsアプリでは、マイグレーションで使うのは `create_table`、`add_column`、`add_index` などのActiveRecord DSLだけである。これらは全て `schema.rb` に反映されるので、`schema.rb` からのロードでもマイグレーション実行でも結果は同じになる。だからこそ、この問題は小規模なCRUDアプリでは表面化しない。

RLS以外でも、`execute` が必要になるケースはある。

- トリガー / ストアドファンクション
- カスタムのCHECK制約
- テーブルパーティショニング
- PostgreSQL固有の拡張機能（pg_trgm等）
- CREATE ROLE / GRANT などの権限管理

これらを使うプロジェクトでは、`schema.rb` では不十分であり、`structure.sql` を使う必要がある。

## 解決策

### 1. schema_format を :sql に変更する

`config/application.rb` に以下を追加する。

```ruby
module Workspace
  class Application < Rails::Application
    # ...
    config.active_record.schema_format = :sql
  end
end
```

これにより、`db:migrate` 後に `db/schema.rb` ではなく `db/structure.sql`（`pg_dump` の出力）が生成されるようになる。`structure.sql` にはRLSポリシー、GRANT文、トリガーなど、`execute` で実行した内容も含まれる。

新規環境で `db:create` した際も `structure.sql` からロードされるため、RLSポリシーやGRANT文が正しく再現される。

### 2. CREATE ROLE はDBコンテナの初期化スクリプトで行う

`structure.sql` にも含まれないものが1つある。`CREATE ROLE` だ。

PostgreSQLのロールはクラスタレベルのオブジェクトであり、特定のデータベースに属さない。`pg_dump` はデータベース単位のダンプなので、ロール定義は出力されない。

そもそも、`CREATE ROLE` をマイグレーションに含めること自体が責務分離として不自然である。

- マイグレーション → DBスキーマの管理（テーブル、インデックス、ポリシー等）
- ロール管理 → インフラ / DB運用レイヤー

ロールは環境によってパスワードや権限が異なることが多く、マイグレーションの再現性も壊れやすい。Dockerの初期化スクリプトやIaCで管理するのが適切だ。

PostgreSQL公式Dockerイメージは、`/docker-entrypoint-initdb.d/` ディレクトリに置いたSQLファイルをコンテナ初回起動時に自動実行する仕組みを持っている。

`db/init/01_create_rls_role.sql` を作成する。

```sql
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rails_user') THEN
    CREATE ROLE rails_user WITH LOGIN PASSWORD 'rails_password' NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
```

`.devcontainer/docker-compose.yml` の `db` サービスにマウントを追加する。

```yaml
db:
  image: postgres:17
  environment:
    POSTGRES_PASSWORD: password
  ports:
    - "5432:5432"
  volumes:
    - pgdata:/var/lib/postgresql/data
    - ../db/init:/docker-entrypoint-initdb.d # 追加
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 5s
    timeout: 5s
    retries: 5
```

なお、マイグレーションファイルからも `CREATE ROLE` を削除し、GRANT文のみ残す形に修正した。ロール作成はインフラレイヤーの責務として完全に分離している。

## 修正後の検証

ボリュームを完全に削除してDevContainerを再作成し、クリーンな状態から実行した。

```bash
$ bin/rails db:create
Created database 'tenant_manager_development'
Created database 'tenant_manager_test'

$ bin/rails db:migrate
== 20260426025717 CreateTenants: migrating ====================================
-- create_table(:tenants)
   -> 0.0255s
...
== 20260426025740 CreateRlsRole: migrating ====================================
-- execute("DO $$ BEGIN\n  IF NOT EXISTS ...")
   -> 0.0172s
-- execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES ...")
   -> 0.0045s
...
== 20260426025741 EnableRlsPolicies: migrating ================================
-- execute("ALTER TABLE users ENABLE ROW LEVEL SECURITY;")
   -> 0.0035s
-- execute("CREATE POLICY users_tenant_isolation ON users ...")
   -> 0.0048s
...

$ bin/rails db:seed
Seed completed:
  Tenants:  2
  Users:    2
  Projects: 3
  Tasks:    7

$ psql -U postgres -h db -c "\du"
                              List of roles
 Role name  |                         Attributes
------------+------------------------------------------------------------
 postgres   | Superuser, Create role, Create DB, Replication, Bypass RLS
 rails_user |
```

`db:migrate` でマイグレーションが正しく実行され、`rails_user` ロールも作成されている。

## Railsマイグレーションの守備範囲を整理する

今回の件で、Railsのマイグレーション機構がカバーする範囲を改めて整理できた。

| 対象                          | schema.rb  | structure.sql | マイグレーション実行 |
| ----------------------------- | ---------- | ------------- | -------------------- |
| create_table / add_column 等  | 含まれる   | 含まれる      | 実行される           |
| execute（RLS / トリガー等）   | 含まれない | 含まれる      | 実行される           |
| CREATE ROLE（クラスタレベル） | 含まれない | 含まれない    | 実行される           |

「マイグレーション実行」の列は全て「実行される」だが、スキーマファイル（`schema.rb` / `structure.sql`）が存在する環境では、`db:migrate` が空のDBに対してスキーマファイルをロードする最適化が働き、マイグレーション自体がスキップされるため、2行目と3行目は実質的に実行されない。これが今回の落とし穴だった。

`execute` を使うプロジェクトでは `schema_format = :sql` にすること。`CREATE ROLE` のようなクラスタレベルの操作はDBコンテナの初期化スクリプトに分離すること。この2点を押さえておけば、同じ問題は回避できたはずだ。

## まとめ

- Railsのデフォルト設定（`schema_format = :ruby`）では、`schema.rb` にActiveRecord DSLで表現できない `execute` の内容は保持されない
- 空のDBに対して `db:migrate` を実行すると、Railsの内部最適化によりスキーマファイルがロードされ、`schema_migrations` に全バージョンが記録されるため、マイグレーションが全てスキップされる
- 結果として、`execute` で書いた `CREATE ROLE`、`ENABLE ROW LEVEL SECURITY`、`CREATE POLICY` などは一度も実行されない
- 通常のCRUD系アプリでは `schema.rb` で十分だが、RLSやトリガーなどを使うプロジェクトでは `config.active_record.schema_format = :sql` が必須
- PostgreSQLのロール（`CREATE ROLE`）はクラスタレベルのオブジェクトであり、`structure.sql` にも含まれないため、DBコンテナの初期化スクリプト（`docker-entrypoint-initdb.d`）で作成する必要がある

## 教訓

- Railsのマイグレーションは「DB構造」を管理するものであり、「DBの振る舞い（権限・ポリシー）」は完全には表現できない
- DB固有機能（RLS、トリガー、ロール）を使う場合、`schema.rb` に依存する設計は破綻する
- Railsだけで完結させようとせず、DB / インフラの責務分離を前提に設計する必要がある
