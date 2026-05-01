> 🇺🇸 [English version here](testing.md)

# テスト

本プロジェクトではRSpecをテストフレームワークとして使用している。



## 技術スタック

| カテゴリ        | 技術              | 用途                                       |
| --------------- | ----------------- | ------------------------------------------ |
| テストフレームワーク | rspec-rails  | RSpecのRails統合                           |
| テストデータ    | factory_bot_rails | 宣言的なテストデータ生成                   |
| マッチャー      | shoulda-matchers  | バリデーション/アソシエーションのワンライナーテスト |
| HTTPスタブ      | webmock           | 外部HTTPリクエストのスタブ(OPAなど)        |



## ディレクトリ構成

```
spec/
├── factories/
│   └── factories.rb        # FactoryBot定義(Tenant, User, Project, Task)
├── models/
│   ├── tenant_spec.rb      # バリデーションとアソシエーション
│   ├── user_spec.rb        # バリデーション、アソシエーション、.from_omniauth
│   ├── project_spec.rb     # バリデーションとアソシエーション
│   └── task_spec.rb        # バリデーションとアソシエーション
├── services/
│   └── opa_client_spec.rb  # OPA許可 / 拒否 / 到達不能
├── requests/
│   ├── projects_spec.rb    # GET /projects
│   └── tasks_spec.rb       # GET/PATCH tasks, OPA拒否
├── support/
│   └── opa_helper.rb       # stub_opa_allow / stub_opa_denyヘルパー
├── rails_helper.rb
└── spec_helper.rb
```



## テストの実行

DevContainer内で以下のように実行する。

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



## テスト設計方針

### マルチテナンシー(acts_as_tenant)

`rails_helper.rb`に`:tenant`メタデータが指定された場合に`ActsAsTenant.with_tenant`でラップする`around`フックを含めている。リクエストスペックでは、本番の動作に合わせてサブドメイン（`host!`）でテナントを解決する。

### OPA認可

OPAへの全外部HTTP呼び出しはWebMockでスタブ化している。`spec/support/opa_helper.rb`に2つのヘルパーを用意した。

| ヘルパー         | 動作                              |
| ---------------- | --------------------------------- |
| `stub_opa_allow` | OPAが`{ "result": true }`を返す   |
| `stub_opa_deny`  | OPAが`{ "result": false }`を返す  |

OpaClientサービススペックではフェイルクローズのケースもカバーしている。OPAに到達できない場合、アクセスは拒否される。

### PostgreSQL RLS

テスト環境では、RLS用の`SET ROLE` / `RESET ROLE`コマンドはリクエストスペックでスタブ化している。テストデータベースに`rails_user`ロールが存在しない可能性があるためである。テナント分離は`acts_as_tenant`のスコーピングを通じてテストしている。

### 認証(Devise)

リクエストスペックでは`Devise::Test::IntegrationHelpers`（`type: :request`に対してインクルード）を使用して`sign_in`を直接呼び出し、Auth0のOAuthフローをバイパスしている。



## テストカバレッジサマリー

| レイヤー | テスト対象                                              |
| -------- | ------------------------------------------------------- |
| Models   | バリデーション、アソシエーション、`User.from_omniauth`  |
| Services | OpaClient — 許可、拒否、接続障害（フェイルクローズ）    |
| Requests | 認証、OPA認可、CRUD操作                                 |
