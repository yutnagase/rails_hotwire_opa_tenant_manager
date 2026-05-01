> 🇺🇸 [English version here](testing.md)

# テスト

本プロジェクトでは **RSpec** をテストフレームワークとして使用しています。

---

## 技術スタック

| カテゴリ        | 技術              | 用途                                       |
| --------------- | ----------------- | ------------------------------------------ |
| テストフレームワーク | rspec-rails  | RSpec の Rails 統合                        |
| テストデータ    | factory_bot_rails | 宣言的なテストデータ生成                   |
| マッチャー      | shoulda-matchers  | バリデーション/アソシエーションのワンライナーテスト |
| HTTP スタブ     | webmock           | 外部 HTTP リクエストのスタブ (OPA など)    |

---

## ディレクトリ構成

```
spec/
├── factories/
│   └── factories.rb        # FactoryBot 定義 (Tenant, User, Project, Task)
├── models/
│   ├── tenant_spec.rb      # バリデーションとアソシエーション
│   ├── user_spec.rb        # バリデーション、アソシエーション、.from_omniauth
│   ├── project_spec.rb     # バリデーションとアソシエーション
│   └── task_spec.rb        # バリデーションとアソシエーション
├── services/
│   └── opa_client_spec.rb  # OPA 許可 / 拒否 / 到達不能
├── requests/
│   ├── projects_spec.rb    # GET /projects
│   └── tasks_spec.rb       # GET/PATCH tasks, OPA 拒否
├── support/
│   └── opa_helper.rb       # stub_opa_allow / stub_opa_deny ヘルパー
├── rails_helper.rb
└── spec_helper.rb
```

---

## テストの実行

DevContainer 内で：

```bash
# 全テストスイート
bundle exec rspec

# カテゴリ別
bundle exec rspec spec/models/
bundle exec rspec spec/services/
bundle exec rspec spec/requests/

# 単一ファイルまたは行指定
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/models/user_spec.rb:30
```

---

## テスト設計方針

### マルチテナンシー (acts_as_tenant)

`rails_helper.rb` に `:tenant` メタデータが指定された場合に `ActsAsTenant.with_tenant` でラップする `around` フックを含む。リクエストスペックでは、本番の動作に合わせてサブドメイン（`host!`）でテナントを解決。

### OPA 認可

OPA への全外部 HTTP 呼び出しは WebMock でスタブ化。`spec/support/opa_helper.rb` に 2 つのヘルパーを用意：

| ヘルパー         | 動作                              |
| ---------------- | --------------------------------- |
| `stub_opa_allow` | OPA が `{ "result": true }` を返す  |
| `stub_opa_deny`  | OPA が `{ "result": false }` を返す |

OpaClient サービススペックでは**フェイルクローズ**のケースもカバー — OPA に到達できない場合、アクセスは拒否される。

### PostgreSQL RLS

テスト環境では、RLS 用の `SET ROLE` / `RESET ROLE` コマンドはリクエストスペックでスタブ化。テストデータベースに `rails_user` ロールが存在しない可能性があるため。テナント分離は `acts_as_tenant` スコーピングを通じてテスト。

### 認証 (Devise)

リクエストスペックでは `Devise::Test::IntegrationHelpers`（`type: :request` に対してインクルード）を使用して `sign_in` を直接呼び出し、Auth0 OAuth フローをバイパス。

---

## テストカバレッジサマリー

| レイヤー | テスト対象                                              |
| -------- | ------------------------------------------------------- |
| Models   | バリデーション、アソシエーション、`User.from_omniauth`  |
| Services | OpaClient — 許可、拒否、接続障害（フェイルクローズ）    |
| Requests | 認証、OPA 認可、CRUD 操作                               |
