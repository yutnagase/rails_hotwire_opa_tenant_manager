> 🇺🇸 [English version here](design.md)

# 設計ドキュメント: Rails Hotwire × acts_as_tenant × OPA マルチテナント タスク管理アプリ

## 1. プロジェクト概要

B2B 向けプロジェクト・タスク管理ツール。  
セキュリティ（マルチテナント分離、RLS、OPA 認可）とHotwire によるモダンな UX に焦点を当てた MVP。

### 画面構成（3 画面）

| #   | 画面           | パス                              | 説明                             |
| --- | -------------- | --------------------------------- | -------------------------------- |
| 1   | プロジェクト一覧 | `/projects` (ルート)            | テナント内の全プロジェクトを一覧表示 |
| 2   | タスク一覧     | `/projects/:project_id/tasks`     | プロジェクト配下のタスク一覧     |
| 3   | タスク詳細     | `/projects/:project_id/tasks/:id` | タスク詳細表示とステータス更新   |

---

## 2. 技術スタック

| カテゴリ              | 技術                                 | バージョン / 詳細                    |
| --------------------- | ------------------------------------ | ------------------------------------ |
| 言語                  | Ruby                                 | 3.4.9                                |
| フレームワーク        | Ruby on Rails                        | 8.1.3                                |
| データベース          | PostgreSQL                           | 17                                   |
| フロントエンド        | Hotwire (Turbo Drive / Turbo Frames) | importmap 経由                       |
| アセットパイプライン  | Propshaft                            | -                                    |
| 認証                  | Devise + omniauth-auth0              | Auth0 Organizations 向け設計         |
| 認可                  | Open Policy Agent (OPA)              | Docker コンテナとして実行            |
| マルチテナンシー      | acts_as_tenant                       | アプリケーション層のスコープ制御     |
| DB 行レベルセキュリティ | PostgreSQL RLS                     | DB 層の多層防御                      |
| JWT                   | ruby-jwt                             | トークン検証                         |
| テスト高速化          | test-prof                            | 認可テスト用                         |
| テストフレームワーク  | rspec-rails                          | BDD スタイルのテスト                 |
| テストデータ          | factory_bot_rails                    | 宣言的なテストデータ生成             |
| テストマッチャー      | shoulda-matchers                     | バリデーション/アソシエーションのワンライナーテスト |
| HTTP スタブ           | webmock                              | 外部 HTTP リクエストのスタブ (OPA)   |
| CI                    | GitHub Actions                       | Brakeman / importmap audit / RuboCop |

---

## 3. アーキテクチャ

### 3.1 全体構成

![アーキテクチャ図](images/architecture.svg)

### 3.2 DevContainer 構成

`docker-compose.yml` で 3 つのサービスを起動：

| サービス | イメージ                        | ポート | 役割                  |
| -------- | ------------------------------- | ------ | --------------------- |
| app      | ruby:3.4 (カスタム Dockerfile)  | 8080   | Rails アプリケーション |
| db       | postgres:17                     | 5432   | データベース          |
| opa      | openpolicyagent/opa:latest      | 8181   | ポリシーエンジン      |

### 3.3 リクエストフロー

![リクエストフロー図](images/request_flow.svg)

---

## 4. データベース設計

### 4.1 ER 図

```
tenants 1──* users
tenants 1──* projects
tenants 1──* tasks
projects 1──* tasks
users 1──* tasks (任意)
```

### 4.2 テーブル定義

#### tenants

| カラム     | 型       | 制約             | 説明             |
| ---------- | -------- | ---------------- | ---------------- |
| id         | bigint   | PK               |                  |
| name       | string   | NOT NULL         | テナント名       |
| subdomain  | string   | NOT NULL, UNIQUE | サブドメイン識別子 |
| created_at | datetime | NOT NULL         |                  |
| updated_at | datetime | NOT NULL         |                  |

#### users

| カラム     | 型       | 制約                                 | 説明                           |
| ---------- | -------- | ------------------------------------ | ------------------------------ |
| id         | bigint   | PK                                   |                                |
| tenant_id  | bigint   | NOT NULL, FK(tenants)                | 所属テナント                   |
| auth0_uid  | string   | NOT NULL, UNIQUE(tenant_id)          | Auth0 ユーザー ID              |
| name       | string   | NOT NULL                             | 表示名                         |
| email      | string   | NOT NULL                             | メールアドレス                 |
| role       | string   | NOT NULL, DEFAULT 'member'           | 権限ロール                     |
| seed_admin | boolean  | NOT NULL, DEFAULT false              | 初期管理者ロールの保護         |
| created_at | datetime | NOT NULL                             |                                |
| updated_at | datetime | NOT NULL                             |                                |

ロール種別：

| ロール | 説明                             |
| ------ | -------------------------------- |
| admin  | 管理者 — 全操作可能              |
| member | 一般社員 — 閲覧、作成、更新     |
| guest  | 外部協力者 — 閲覧のみ           |

#### projects

| カラム     | 型       | 制約                  | 説明         |
| ---------- | -------- | --------------------- | ------------ |
| id         | bigint   | PK                    |              |
| tenant_id  | bigint   | NOT NULL, FK(tenants) | 所属テナント |
| name       | string   | NOT NULL              | プロジェクト名 |
| created_at | datetime | NOT NULL              |              |
| updated_at | datetime | NOT NULL              |              |

#### tasks

| カラム     | 型       | 制約                     | 説明                         |
| ---------- | -------- | ------------------------ | ---------------------------- |
| id         | bigint   | PK                       |                              |
| tenant_id  | bigint   | NOT NULL, FK(tenants)    | 所属テナント                 |
| project_id | bigint   | NOT NULL, FK(projects)   | 所属プロジェクト             |
| user_id    | bigint   | FK(users), nullable      | 担当者（未割当可）           |
| name       | string   | NOT NULL                 | タスク名                     |
| status     | string   | NOT NULL, DEFAULT 'todo' | ステータス                   |
| created_at | datetime | NOT NULL                 |                              |
| updated_at | datetime | NOT NULL                 |                              |

ステータス種別: `todo` / `doing` / `done`

---

## 5. マルチテナント設計

### 5.1 テナント分離戦略

**カラムベースの分離** — 全テーブルに `tenant_id` カラムを持ち、アプリケーション層とデータベース層の両方で分離を実現。

### 5.2 テナント識別

サブドメインベースの識別を使用。`request.subdomain` からテナントを解決。

- ローカル: `company-a.localhost:8080`
- 開発環境では `config.action_dispatch.tld_length = 0` を設定し、localhost でのサブドメイン認識を有効化

### 5.3 acts_as_tenant (アプリケーション層)

`ApplicationController` で `set_current_tenant_through_filter` を宣言し、`around_action :scope_to_tenant` で各リクエストにテナントを設定。

各モデルで `acts_as_tenant :tenant` を宣言し、Active Record クエリに自動的に `WHERE tenant_id = ?` を付加。

対象モデル: `User`, `Project`, `Task`

### 5.4 テナントスコープの一時的な無効化

`ActsAsTenant.without_tenant` は `db/seeds.rb` でのみ使用。本番リクエストパスでは使用しない。

---

## 6. PostgreSQL RLS (Row Level Security) 設計

acts_as_tenant によるアプリケーション層の分離に加え、RLS がデータベース層で多層防御を提供。アプリケーション層のスコーピングにバグがあっても、データベースが他テナントのデータへのアクセスを防止。

- DB はデフォルトで `postgres`（スーパーユーザー、BYPASSRLS）として接続
- リクエスト中は `SET ROLE` で `rails_user`（NOBYPASSRLS）に切り替え
- RLS ポリシーが全テナントスコープテーブルで `tenant_id = current_setting('app.current_tenant_id')` を強制
- `schema_migrations` と `ar_internal_metadata` は RLS 対象外

> RLS の概念、ポリシー、実装の詳細は [rls.ja.md](rls.ja.md) を参照。

---

## 7. OPA 認可設計

OPA は**垂直方向のアクセス制御**（テナント内のロールベース権限）を担当し、RLS と acts_as_tenant はテナント間の水平方向の分離を担当。

- OPA は Docker コンテナとして実行し、`http://opa:8181/v1/data/authz/allow` で Rego ポリシーを評価
- `ApplicationController` が `before_action :authorize_with_opa` で毎リクエスト OPA を呼び出し
- フェイルセーフ設計: OPA に到達できない場合はアクセスを拒否

| ロール \ アクション | read | create | update | delete |
| ------------------- | ---- | ------ | ------ | ------ |
| admin               | ✅   | ✅     | ✅     | ✅     |
| member              | ✅   | ✅     | ✅     | ❌     |
| guest               | ✅   | ❌     | ❌     | ❌     |

> OPA の概念、Rego ポリシー、統合の詳細は [opa.ja.md](opa.ja.md) を参照。

---

## 8. 認証設計

Devise + omniauth-auth0 による OAuth2 認証。

- Auth0 は**本人確認のみ**を担当 — アプリケーションにパスワードは保存しない
- ロール管理は Rails 内で完結（`users.role` カラム）
- シード管理者ユーザーは `seed_admin: true` で事前作成し、初回ログイン時にメールマッチで Auth0 とリンク
- Auth0 コールバックで作成される新規ユーザーには `guest` ロールを割り当て
- コールバック時にサブドメインを使用して正しいテナントにユーザーをスコーピング
- ログインページ (`/dev_session/new`) は設定に応じて Auth0 ボタンまたは開発用ユーザー選択リストを表示

> Auth0 フロー、Devise 設定、マルチテナント認証の詳細は [auth0.ja.md](auth0.ja.md) を参照。

---

## 9. Hotwire 設計

### 9.1 Turbo Drive

全ページナビゲーションで Turbo Drive を有効化。`<body>` を置換して SPA ライクなスムーズな遷移を実現。importmap で `@hotwired/turbo-rails` を読み込み。

### 9.2 Turbo Frames

タスクステータス更新に Turbo Frames を使用し、フルリロードなしの部分更新を実現。

#### タスク一覧でのステータス更新

各タスク行を `turbo_frame_tag dom_id(task)` でラップ。ステータスセレクトボックスの変更時に `requestSubmit()` でフォームを送信。サーバーが `_task.html.erb` パーシャルを返し、該当行のみを更新。

#### タスク詳細でのステータス更新

ステータスセクションを `turbo_frame_tag "task_status"` でラップ。変更時にサーバーが `_task_status.html.erb` パーシャルを返す。`TasksController#update` は `turbo_frame_request_id` をチェックしてどのパーシャルをレンダリングするか判定。

### 9.3 Stimulus

Stimulus コントローラの基盤は設定済み（`app/javascript/controllers/`）。カスタムコントローラは未実装で、ステータス変更はインライン JS（`onchange: "this.form.requestSubmit()"`）を使用。

---

## 10. ルーティング

```ruby
root "projects#index"

resources :projects, only: [:index] do
  resources :tasks, only: [:index, :show, :update]
end
```

| メソッド | パス                            | アクション     | 説明             |
| -------- | ------------------------------- | -------------- | ---------------- |
| GET      | /projects                       | projects#index | プロジェクト一覧 |
| GET      | /projects/:project_id/tasks     | tasks#index    | タスク一覧       |
| GET      | /projects/:project_id/tasks/:id | tasks#show     | タスク詳細       |
| PATCH    | /projects/:project_id/tasks/:id | tasks#update   | タスクステータス更新 |

MVP として最小限の CRUD のみを公開。create / destroy は現時点ではスコープ外。

---

## 11. ディレクトリ構成

```
rails_hotwire_opa_tenant_manager/
├── .devcontainer/
│   ├── Dockerfile          # Ruby 3.4 + PostgreSQL クライアント
│   ├── devcontainer.json   # VS Code DevContainer 設定
│   └── docker-compose.yml  # 3 サービス: app / db / opa
├── .github/
│   └── workflows/
│       └── ci.yml          # Brakeman / importmap audit / RuboCop
├── app/
│   ├── controllers/
│   │   ├── concerns/
│   │   ├── users/
│   │   │   ├── omniauth_callbacks_controller.rb  # Auth0 コールバック
│   │   │   └── sessions_controller.rb            # サインアウト
│   │   ├── application_controller.rb  # テナント制御、認証、OPA 認可
│   │   ├── dev_sessions_controller.rb # ログインページ (Auth0 / 開発用ユーザー選択)
│   │   ├── projects_controller.rb
│   │   └── tasks_controller.rb
│   ├── models/
│   │   ├── tenant.rb       # has_many :users, :projects, :tasks
│   │   ├── user.rb         # acts_as_tenant, devise :omniauthable
│   │   ├── project.rb      # acts_as_tenant
│   │   └── task.rb         # acts_as_tenant, belongs_to :project/:user
│   ├── services/
│   │   └── opa_client.rb   # OPA HTTP クライアント
│   └── views/
│       ├── layouts/
│       │   └── application.html.erb
│       ├── projects/
│       │   └── index.html.erb
│       └── tasks/
│           ├── _task.html.erb          # タスク行パーシャル (Turbo Frame)
│           ├── _task_status.html.erb   # ステータスパーシャル (Turbo Frame)
│           ├── index.html.erb
│           └── show.html.erb
├── config/
│   ├── database.yml        # postgres (スーパーユーザー) として接続
│   ├── initializers/
│   │   └── devise.rb       # Auth0 OmniAuth 設定
│   └── routes.rb
├── db/
│   ├── migrate/
│   │   ├── *_create_tenants.rb
│   │   ├── *_create_users.rb
│   │   ├── *_create_projects.rb
│   │   ├── *_create_tasks.rb
│   │   ├── *_create_rls_role.rb        # rails_user ロール作成
│   │   └── *_enable_rls_policies.rb    # RLS 有効化 + ポリシー作成
│   ├── schema.rb
│   └── seeds.rb            # 開発用シードデータ
├── docs/
│   ├── README.md           # ドキュメントインデックス
│   ├── design.md           # 本設計ドキュメント
│   ├── rls.md              # RLS 詳細ドキュメント
│   ├── opa.md              # OPA 詳細ドキュメント
│   ├── auth0.md            # Auth0 認証ドキュメント
│   ├── testing.md          # テスト戦略と構成
│   └── images/             # アーキテクチャとフローのダイアグラム
├── spec/
│   ├── factories/          # FactoryBot 定義
│   ├── models/             # モデルスペック
│   ├── services/           # サービススペック (OpaClient)
│   ├── requests/           # リクエストスペック (コントローラ)
│   ├── support/            # 共有ヘルパー (OPA スタブ)
│   ├── rails_helper.rb
│   └── spec_helper.rb
└── opa/
    └── policy/
        └── authz.rego      # OPA 認可ポリシー
```

---

## 12. セキュリティ設計サマリー

### 多層防御アーキテクチャ

```
[レイヤー 1] サブドメインによるテナント識別
    ↓
[レイヤー 2] Devise + Auth0 による認証
    ↓
[レイヤー 3] acts_as_tenant によるアプリケーション層のテナント分離
    ↓
[レイヤー 4] OPA によるロールベースの認可
    ↓
[レイヤー 5] PostgreSQL RLS によるデータベース層のテナント分離
```

| レイヤー              | 防御対象                          | 実装                                 |
| --------------------- | --------------------------------- | ------------------------------------ |
| テナント識別          | 誤ったテナントへのアクセス        | サブドメイン → テナント検索          |
| 認証                  | 未認証アクセス                    | Devise + Auth0                       |
| アプリ層の分離        | テナント間クエリ                  | acts_as_tenant (自動 WHERE)          |
| ロール認可            | 権限外の操作                      | OPA (Rego ポリシー)                  |
| DB 層の分離           | アプリケーションバグによるデータ漏洩 | PostgreSQL RLS                    |

---

## 13. 環境変数

| 変数                  | 説明                                             |
| --------------------- | ------------------------------------------------ |
| DB_HOST               | PostgreSQL ホスト                                |
| DB_PORT               | PostgreSQL ポート                                |
| DB_SUPERUSER          | DB 接続ユーザー（スーパーユーザー）              |
| DB_SUPERUSER_PASSWORD | DB 接続パスワード                                |
| RLS_ROLE              | RLS 制限ロール名                                 |
| RLS_ROLE_PASSWORD     | RLS ロールパスワード                             |
| OPA_URL               | OPA エンドポイント                               |
| AUTH0_CLIENT_ID       | Auth0 クライアント ID                            |
| AUTH0_CLIENT_SECRET   | Auth0 クライアントシークレット                   |
| AUTH0_DOMAIN          | Auth0 ドメイン                                   |
| SEED_ADMIN_EMAIL_COMPANY_A | Company A 初期管理者のメールアドレス        |
| SEED_ADMIN_EMAIL_COMPANY_B | Company B 初期管理者のメールアドレス        |

---

## 14. シードデータ

2 つのテナントと初期管理者ユーザーをシード：

| テナント  | サブドメイン | ユーザー        | プロジェクト                      | タスク  |
| --------- | ------------ | --------------- | --------------------------------- | ------- |
| Company A | company-a    | Admin A (admin) | Website Redesign, API Development | 5 タスク |
| Company B | company-b    | Admin B (admin) | Mobile App                        | 2 タスク |

シード管理者ユーザーは `seed_admin: true` でロール変更不可。  
管理者メールアドレスは環境変数（`SEED_ADMIN_EMAIL_COMPANY_A`, `SEED_ADMIN_EMAIL_COMPANY_B`）から読み込み。  
追加ユーザーは Auth0 初回ログイン時に `guest` として作成。

---

## 15. CI/CD

GitHub Actions で以下のジョブを自動実行：

| ジョブ    | 説明                                                 |
| --------- | ---------------------------------------------------- |
| scan_ruby | Brakeman によるセキュリティ静的解析                  |
| scan_js   | importmap audit による JS 依存関係の脆弱性チェック   |
| lint      | RuboCop によるコードスタイルチェック                 |
| test      | RSpec テストスイート                                 |

---

## 16. 当初仕様からの変更点

| 項目               | 当初仕様                                    | 実装                                                                                                        |
| ------------------ | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Puma ポート        | 8080                                        | 3000 (Puma デフォルト)。docker-compose でポートマッピング 8080:8080 を設定                                   |
| DB 接続            | マイグレーションとランタイムで別ユーザー    | 単一接続 (postgres) + `SET ROLE` による動的切り替え。コネクションプール管理を簡素化                          |
| Stimulus           | 使用対象として言及                          | 基盤のみ。ステータス変更はインライン JS (`onchange="this.form.requestSubmit()"`) を使用                      |
| タスク CRUD        | 特に制限なし                                | MVP として index / show / update のみ公開。create / destroy は未実装                                        |
| Rails モジュール名 | 未指定                                      | `Workspace` として生成 (`config/application.rb`)                                                            |
