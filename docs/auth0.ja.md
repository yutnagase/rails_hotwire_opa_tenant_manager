> 🇺🇸 [English version here](auth0.md)

# Auth0 による認証

このドキュメントでは、Devise と Auth0 を使用した本プロジェクトの認証の仕組みと、マルチテナントアーキテクチャとの統合方法を記述します

## Auth0 とは？

Auth0 は、ユーザー認証を代行するクラウドベースのアイデンティティ管理のプラットフォームサービスです。
ログインフォーム、パスワードハッシュ、セッション管理をゼロから構築する代わりに、これらの責務を Auth0 に委譲します。

Auth0 がサポートする機能
- ソーシャルログイン (Google, GitHub など)
- ユーザー名/パスワード認証
- 多要素認証 (MFA)
- 組織ベースのマルチテナンシー (Auth0 Organizations)

本プロジェクトでは、Auth0 は認証（本人確認）のみに使用。ロール管理は Rails 内で管理。



## 設計原則

| 関心事 | 責務 |
|---|---|
| 認証（このユーザーは誰か？） | Auth0 |
| ロール管理（このユーザーは何ができるか？） | Rails DB (`users.role`) |
| 認可の強制 | OPA |

Auth0 はロール、権限、テナントメンバーシップを管理しない。ユーザーが本人であることの検証（例: Google OAuth 経由）のみを行う。全てのビジネスレベルのアクセス制御は Rails アプリケーション内で管理。



## Auth0 認証の仕組み（OAuth2 フロー）

```
1. ユーザーが company-a.localhost:8080 にアクセス
2. Rails がセッションなしを検出 → ログインページを表示
3. ユーザーが「Sign in with Auth0」をクリック (POST to /users/auth/auth0)
4. ブラウザが Auth0 Universal Login にリダイレクト
5. ユーザーが認証（例: 「Continue with Google」）
6. Auth0 がユーザー情報付きで /users/auth/auth0/callback にリダイレクト
7. Rails がユーザーを検索または作成し、セッションを確立
8. ユーザーが認証済みになる
```

標準的な OAuth2 Authorization Code フローを採用
Rails アプリケーションはユーザーのパスワードを一切参照しない。Auth0 が全ての認証処理を担当

## ユーザーライフサイクル

### シード管理者ユーザー

初期管理者ユーザーは `db/seeds.rb` で以下の設定で事前作成
- `role: "admin"`
- `seed_admin: true`（ロール変更不可）
- `auth0_uid: "seed|admin_a"`（プレースホルダー、初回ログイン時に更新）
- `email` は環境変数（`SEED_ADMIN_EMAIL_COMPANY_A` など）から設定

### 初回ログイン（メールアドレスベースでの紐づけ）

ユーザーが Auth0 経由で初めてログインすると、`User.from_omniauth` が以下を実行

1. `auth0_uid` で検索 — 見つかれば既存ユーザーを返す（リピーター）
2. テナント内で `email` で検索 — 見つかれば `auth0_uid` を更新してAuth0とRailsアプリを紐づける（シードユーザーの初回ログイン）
3. 見つからなければ `role: "guest"` で新規ユーザーを作成する

これにより、シード管理者ユーザーがメールマッチに基づいて初回ログイン時に Auth0と紐づけされる。

### ロール割り当て

| シナリオ | ロール |
|---|---|
| シード管理者（事前作成） | `admin`（不変、`seed_admin: true`） |
| 新規ユーザー（Auth0 初回ログイン） | `guest` |
| 管理者によるロール変更 | 管理者が他ユーザーのロールを変更可能（将来機能） |



## 概要

### Devise

Devise は Rails で最も広く使われている認証ライブラリ。本プロジェクトでは以下を提供している
- セッション管理（サインイン / サインアウト）
- `current_user` ヘルパー
- `authenticate_user!` before action
- 外部プロバイダー向け OmniAuth 統合

### OmniAuth

`omniauth-auth0`
マルチプロバイダー認証を標準化するRackミドルウェア
OAuth2 ハンドシェイクを自動処理する為のものであり、gemにAuth0のプロバイダーとして追加する

`omniauth-rails_csrf_protection` 
RailsのCSRFトークンとOmniAuth のミドルウェアレベルでのCSRF 検証を橋渡しするために必要（OmniAuth 2.x 以降で必須）



## 本プロジェクトでの認証実装

### Devise + Auth0 設定

Auth0はDeviseイニシャライザ
OmniAuthプロバイダーとして設定する

```ruby
# config/initializers/devise.rb
config.omniauth :auth0,
  ENV.fetch("AUTH0_CLIENT_ID", "your_client_id"),
  ENV.fetch("AUTH0_CLIENT_SECRET", "your_client_secret"),
  ENV.fetch("AUTH0_DOMAIN", "your_tenant.auth0.com"),
  callback_path: "/users/auth/auth0/callback",
  authorize_params: { scope: "openid profile email" }
```

| パラメータ | 説明 |
|---|---|
| `AUTH0_CLIENT_ID` | Auth0 に対してこのアプリケーションを識別 |
| `AUTH0_CLIENT_SECRET` | Auth0 との安全な通信のためのシークレットキー |
| `AUTH0_DOMAIN` | Auth0 テナントドメイン (例: `example.auth0.com`) |
| `callback_path` | 認証後に Auth0 がリダイレクトする先 |
| `scope` | 要求するユーザー情報: OpenID アイデンティティ、プロフィール、メール |

### User モデル

User モデルは OmniAuth のみで認証出来る用に設定する
パスワードベースのログインが必要ない

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: [:auth0]

  acts_as_tenant :tenant

  ROLES = %w[admin member guest].freeze

  validates :auth0_uid, presence: true, uniqueness: { scope: :tenant_id }
  validates :name, presence: true
  validates :email, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  def self.from_omniauth(auth, tenant)
    # 1. auth0_uid で既にリンク済み
    user = find_by(auth0_uid: auth.uid, tenant: tenant)
    return user if user

    # 2. メールマッチでシードユーザーをリンク
    user = find_by(email: auth.info.email, tenant: tenant)
    if user
      user.update!(auth0_uid: auth.uid, name: auth.info.name || user.name)
      return user
    end

    # 3. guest として新規ユーザーを作成
    create!(
      tenant: tenant,
      auth0_uid: auth.uid,
      email: auth.info.email,
      name: auth.info.name || auth.info.email,
      role: "guest"
    )
  end
end
```

ポイント
- `devise :omniauthable`
  - OmniAuthのみ有効。パスワードは保存しない
- `auth0_uid`
  - テナントごとにユニークとなる
  `auth0_uid` + `tenant_id` の複合ユニークインデックス
- `seed_admin`
  - `true` の場合、ユーザーのロールは変更不可
- `from_omniauth`
  - 3段階の検索: auth0_uid → email → 新規 guest

### ルーティング

```ruby
# config/routes.rb
devise_for :users,
  controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  },
  skip: [:registrations, :passwords, :confirmations]

devise_scope :user do
  delete "sign_out", to: "users/sessions#destroy", as: :destroy_user_session
end

resource :dev_session, only: [:new, :create]
```

スキップしたDeviseモジュール
- `registrations`
  - ユーザーは Auth0 コールバックで作成、セルフ登録なし
- `passwords`
  - パスワード管理は Auth0 が担当
- `confirmations`
  - メール確認は Auth0 が担当

### ログインページ (DevSessionsController)

`/dev_session/new` Auth0, Auth0未設定共有のログインページ

- Auth0 設定済み
  - `/users/auth/auth0` にPOSTする
  - 「Sign in with Auth0」ボタンを表示（外部リダイレクトを許可するため Turbo 無効）
- Auth0 未設定
  - 開発の利便性のためユーザー選択リストを表示

```ruby
# app/controllers/dev_sessions_controller.rb
class DevSessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :authorize_with_opa

  def new
    @auth0_configured = auth0_configured?
    @users = ActsAsTenant.current_tenant.users unless @auth0_configured
  end
end
```

### OmniAuth コールバックコントローラ

Auth0 が認証後にリダイレクトした際に、コールバックを処理するコントローラ

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :auth0
  skip_before_action :authenticate_user!
  skip_before_action :authorize_with_opa

  def auth0
    auth = request.env["omniauth.auth"]
    tenant = Tenant.find_by!(subdomain: request.subdomain)

    @user = User.from_omniauth(auth, tenant)
    sign_in_and_redirect @user, event: :authentication
  end

  def failure
    redirect_to root_path, alert: "Authentication failed."
  end
end
```

フロー
1. `request.env["omniauth.auth"]` から Auth0 ユーザー情報を抽出
2. サブドメインからテナントを解決
3. そのテナント内でユーザーを検索または作成（メールベースのリンク付き）
4. サインインしてアプリケーションにリダイレクト

### Sessions コントローラ

サインアウトは Auth0 設定に応じてログインページまたはルートにリダイレクト

```ruby
# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  skip_before_action :authorize_with_opa, only: :destroy

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    if signed_out
      path = (!auth0_configured? && Rails.env.development?) ? new_dev_session_path : root_path
      redirect_to path, notice: "Signed out."
    end
  end
end
```

### 認証の強制

全リクエストで `ApplicationController` の `before_action :authenticate_user!` により認証を要求

```ruby
# app/controllers/application_controller.rb
def authenticate_user!
  return if user_signed_in?

  redirect_to new_dev_session_path
end

def auth0_configured?
  ENV["AUTH0_CLIENT_ID"].present? && ENV["AUTH0_CLIENT_ID"] != "your_client_id"
end
```

未認証ユーザーの場合はログインページにリダイレクトされ、Auth0 設定に応じてログインを再実行させる


## マルチテナント認証フロー

サブドメインが認証と正しいテナントの接続において重要な役割を果たす

```
1. ユーザーが company-a.localhost:8080 にアクセス
                    ↓
2. scope_to_tenant が "company-a" → Tenant (id: 1) を解決
                    ↓
3. authenticate_user! がセッションをチェック
                    ↓
4. セッションなし → /dev_session/new (ログインページ) にリダイレクト
                    ↓
5. ユーザーが「Sign in with Auth0」をクリック (POST)
                    ↓
6. Auth0 が認証 → /users/auth/auth0/callback にリダイレクト
                    ↓
7. OmniauthCallbacksController#auth0:
   - サブドメインからテナントを解決
   - User.from_omniauth(auth, tenant) を呼び出し
   - auth0_uid、email でリンク、または新規 guest を作成
                    ↓
8. セッション確立 → ユーザーは自テナントのデータのみ参照可能
```

これにより、2つのテナントに同じメールのユーザーがいても、`from_omniauth` が `tenant` でスコーピングするため別々のユーザーとして扱われる仕組みとなる



## 環境変数

| 変数 | 説明 |
|---|---|
| `AUTH0_CLIENT_ID` | Auth0 アプリケーションのクライアント ID |
| `AUTH0_CLIENT_SECRET` | Auth0 アプリケーションのクライアントシークレット |
| `AUTH0_DOMAIN` | Auth0 テナントドメイン |
| `SEED_ADMIN_EMAIL_COMPANY_A` | Company A 初期管理者のメールアドレス（Auth0 ログインメールと一致必須） |
| `SEED_ADMIN_EMAIL_COMPANY_B` | Company B 初期管理者のメールアドレス（Auth0 ログインメールと一致必須） |

これらは `.devcontainer/.env`（git-ignored）に設定し、`docker-compose.yml` 経由で読み込み。



## Auth0 セットアップ要件

Auth0 ダッシュボードで、アプリケーションに以下を設定

| 設定 | 値 |
|---|---|
| Application Type | Regular Web Application |
| Allowed Callback URLs | `http://company-a.localhost:8080/users/auth/auth0/callback, http://company-b.localhost:8080/users/auth/auth0/callback` |
| Allowed Logout URLs | `http://company-a.localhost:8080, http://company-b.localhost:8080` |
| Allowed Web Origins | `http://company-a.localhost:8080, http://company-b.localhost:8080` |

Authentication → Social で少なくとも 1 つのソーシャル接続（例: Google）を有効化。



## Auth0 なしでの開発

Auth0 環境変数が未設定（またはプレースホルダー値のまま）の場合

1. ログインページに Auth0 ボタンの代わりにユーザー選択リストが表示
2. 任意のシードユーザーを選択して直接サインイン可能
3. 外部認証サービスは不要

`bin/rails db:seed` 実行後すぐに開発を開始できる。



## まとめ

| 概念 | 本プロジェクトでの実装 |
|---|---|
| 認証プロバイダー | Auth0 (OAuth2 経由) |
| Rails 統合 | Devise + omniauth-auth0 + omniauth-rails_csrf_protection |
| ユーザー識別 | `auth0_uid` (テナントごとにユニーク) |
| テナントスコーピング | コールバック内でサブドメイン → テナント検索 |
| シードユーザーリンク | Auth0 初回ログイン時のメールベースマッチング |
| 新規ユーザーデフォルトロール | `guest` |
| ロール管理 | Rails DB のみ（Auth0 はロールに使用しない） |
| シード管理者保護 | `seed_admin: true` でロール変更を防止 |
| パスワード保存 | なし — Auth0 に完全委譲 |
| セッション管理 | Devise によるサーバーサイド |
| ログインページ | `/dev_session/new` — Auth0 ボタンまたは開発用ユーザー選択 |
| Turbo 互換性 | Auth0 ボタンは CORS 問題回避のため `data-turbo="false"` を使用 |
