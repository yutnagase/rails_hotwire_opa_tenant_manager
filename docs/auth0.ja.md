> 🇺🇸 [English version here](auth0.md)

# Auth0による認証

このドキュメントでは、DeviseとAuth0を使った認証の仕組みと、マルチテナントアーキテクチャとの統合について記載する。

## Auth0とは

Auth0はクラウドベースのアイデンティティ管理サービスであり、ユーザー認証を代行してくれる。
ログインフォームやパスワードハッシュ、セッション管理をゼロから構築する代わりに、これらの責務をAuth0に委譲する形となる。

Auth0がサポートする機能は以下の通り。
- ソーシャルログイン(Google, GitHubなど)
- ユーザー名/パスワード認証
- 多要素認証(MFA)
- 組織ベースのマルチテナンシー(Auth0 Organizations)

本プロジェクトでは、Auth0は認証（本人確認）のみに使用している。ロール管理はRails側で行う方針である。



## 設計原則

| 関心事 | 責務 |
|---|---|
| 認証（このユーザーは誰か？） | Auth0 |
| ロール管理（このユーザーは何ができるか？） | Rails DB (`users.role`) |
| 認可の強制 | OPA |

Auth0にはロールや権限、テナントメンバーシップの管理はさせていない。本人確認（例: Google OAuth経由）だけを担当させ、ビジネスレベルのアクセス制御はすべてRailsアプリ内で管理している。



## Auth0認証の流れ（OAuth2フロー）

```
1. ユーザーがcompany-a.localhost:8080にアクセス
2. Railsがセッションなしを検出 → ログインページを表示
3. ユーザーが「Sign in with Auth0」をクリック(POST to /users/auth/auth0)
4. ブラウザがAuth0 Universal Loginにリダイレクト
5. ユーザーが認証（例: 「Continue with Google」）
6. Auth0がユーザー情報付きで/users/auth/auth0/callbackにリダイレクト
7. Railsがユーザーを検索または作成し、セッションを確立
8. ユーザーが認証済みとなる
```

標準的なOAuth2 Authorization Codeフローを採用している。
Railsアプリはユーザーのパスワードに一切触れない。認証処理はすべてAuth0が担当する。

## ユーザーライフサイクル

### シード管理者ユーザー

初期管理者は`db/seeds.rb`で事前に作成する。
- `role: "admin"`
- `seed_admin: true`（ロール変更不可とするため）
- `auth0_uid: "seed|admin_a"`（プレースホルダー。初回ログイン時に実際の値で上書きされる）
- `email`は環境変数（`SEED_ADMIN_EMAIL_COMPANY_A`など）から取得

### 初回ログイン（メールアドレスベースの紐づけ）

ユーザーがAuth0経由で初めてログインすると、`User.from_omniauth`が以下の順で処理を行う。

1. `auth0_uid`で検索 — 見つかればそのユーザーを返す（リピーター）
2. テナント内で`email`で検索 — 見つかれば`auth0_uid`を更新して紐づける（シードユーザーの初回ログイン）
3. どちらにも該当しなければ`role: "guest"`で新規作成する

この仕組みにより、シード管理者がメールマッチで初回ログイン時にAuth0と紐づけられる。

### ロール割り当て

| シナリオ | ロール |
|---|---|
| シード管理者（事前作成） | `admin`（変更不可、`seed_admin: true`） |
| 新規ユーザー（Auth0初回ログイン） | `guest` |
| 管理者によるロール変更 | 管理者が他ユーザーのロールを変更可能（将来機能） |



## 使用ライブラリ

### Devise

Railsで最も広く使われている認証ライブラリである。本プロジェクトでは以下の機能を利用している。
- セッション管理（サインイン / サインアウト）
- `current_user`ヘルパー
- `authenticate_user!` before action
- OmniAuth統合

### OmniAuth

`omniauth-auth0`
マルチプロバイダー認証を標準化するRackミドルウェアである。
OAuth2のハンドシェイクを自動処理してくれるため、gemにAuth0プロバイダーとして追加する。

`omniauth-rails_csrf_protection`
RailsのCSRFトークンとOmniAuthのミドルウェアレベルでのCSRF検証を橋渡しするために必要となる。OmniAuth 2.x以降では必須。



## 認証の実装

### Devise + Auth0の設定

Auth0はDeviseのイニシャライザでOmniAuthプロバイダーとして登録する。

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
| `AUTH0_CLIENT_ID` | Auth0に対してこのアプリを識別するためのID |
| `AUTH0_CLIENT_SECRET` | Auth0との安全な通信用シークレット |
| `AUTH0_DOMAIN` | Auth0テナントドメイン(例: `example.auth0.com`) |
| `callback_path` | 認証後にAuth0がリダイレクトしてくる先 |
| `scope` | 要求するユーザー情報: OpenIDアイデンティティ、プロフィール、メール |

### Userモデル

UserモデルはOmniAuthのみで認証する設定としている。パスワードベースのログインは使用しない。

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
    # 1. auth0_uidで既にリンク済み
    user = find_by(auth0_uid: auth.uid, tenant: tenant)
    return user if user

    # 2. メールマッチでシードユーザーをリンク
    user = find_by(email: auth.info.email, tenant: tenant)
    if user
      user.update!(auth0_uid: auth.uid, name: auth.info.name || user.name)
      return user
    end

    # 3. guestとして新規作成
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

ポイントとしては以下の通り。
- `devise :omniauthable` — OmniAuthのみ有効。パスワードは保存しない
- `auth0_uid` — テナントごとにユニーク。`auth0_uid` + `tenant_id`の複合ユニークインデックスを張っている
- `seed_admin` — `true`の場合、ロール変更不可となる
- `from_omniauth` — auth0_uid → email → 新規guestの3段階で検索する

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

スキップしたDeviseモジュールは以下の通り。
- `registrations` — ユーザーはAuth0コールバックで作成するため、セルフ登録は不要
- `passwords` — パスワード管理はAuth0の担当
- `confirmations` — メール確認もAuth0側で行う

### ログインページ(DevSessionsController)

`/dev_session/new`がAuth0設定済み・未設定の両方で使うログインページとなっている。

- Auth0設定済みの場合 → 「Sign in with Auth0」ボタンを表示。外部リダイレクトを許可するためTurboは無効にしている
- Auth0未設定の場合 → 開発用にユーザー選択リストを表示する

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

### OmniAuthコールバックコントローラ

Auth0での認証後にリダイレクトされてきた際のコールバック処理を担当する。

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

処理の流れは以下の通り。
1. `request.env["omniauth.auth"]`からAuth0のユーザー情報を取り出す
2. サブドメインからテナントを特定する
3. そのテナント内でユーザーを探すか新規作成する（メールベースのリンクあり）
4. サインインしてアプリにリダイレクトする

### Sessionsコントローラ

サインアウト時はAuth0の設定状況に応じてリダイレクト先を変えている。

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

全リクエストで`ApplicationController`の`before_action :authenticate_user!`が実行される。

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

未認証の場合はログインページにリダイレクトされ、Auth0の設定に応じたログインをやり直す形となる。



## マルチテナント認証フロー

サブドメインが認証と正しいテナントの紐づけにおいて重要な役割を果たしている。

```
1. ユーザーがcompany-a.localhost:8080にアクセス
                    ↓
2. scope_to_tenantが"company-a" → Tenant(id: 1)を解決
                    ↓
3. authenticate_user!がセッションをチェック
                    ↓
4. セッションなし → /dev_session/newにリダイレクト
                    ↓
5. ユーザーが「Sign in with Auth0」をクリック(POST)
                    ↓
6. Auth0が認証 → /users/auth/auth0/callbackにリダイレクト
                    ↓
7. OmniauthCallbacksController#auth0
   - サブドメインからテナントを解決
   - User.from_omniauth(auth, tenant)を呼び出し
   - auth0_uid、emailでリンク、または新規guestを作成
                    ↓
8. セッション確立 → ユーザーは自テナントのデータのみ参照可能となる
```

2つのテナントに同じメールのユーザーがいても、`from_omniauth`が`tenant`でスコーピングしているため別々のユーザーとして扱われる。



## 環境変数

| 変数 | 説明 |
|---|---|
| `AUTH0_CLIENT_ID` | Auth0アプリケーションのクライアントID |
| `AUTH0_CLIENT_SECRET` | Auth0アプリケーションのクライアントシークレット |
| `AUTH0_DOMAIN` | Auth0テナントドメイン |
| `SEED_ADMIN_EMAIL_COMPANY_A` | Company A初期管理者のメール（Auth0ログインメールと一致させる） |
| `SEED_ADMIN_EMAIL_COMPANY_B` | Company B初期管理者のメール（Auth0ログインメールと一致させる） |

`.devcontainer/.env`（gitignore済み）に記載し、`docker-compose.yml`経由で読み込む。



## Auth0セットアップ

Auth0ダッシュボードで以下を設定しておく必要がある。

| 設定 | 値 |
|---|---|
| Application Type | Regular Web Application |
| Allowed Callback URLs | `http://company-a.localhost:8080/users/auth/auth0/callback, http://company-b.localhost:8080/users/auth/auth0/callback` |
| Allowed Logout URLs | `http://company-a.localhost:8080, http://company-b.localhost:8080` |
| Allowed Web Origins | `http://company-a.localhost:8080, http://company-b.localhost:8080` |

Authentication → Socialで、Googleなどのソーシャル接続を最低1つ有効にしておくこと。



## Auth0なしでの開発

Auth0の環境変数が未設定（またはプレースホルダーのまま）の場合、以下のように動作する。

1. ログインページにAuth0ボタンの代わりにユーザー選択リストが表示される
2. シードユーザーを選んで直接サインインできる
3. 外部の認証サービスは不要

`bin/rails db:seed`を実行すればすぐに開発を始められる。



## まとめ

| 概念 | 本プロジェクトでの実装 |
|---|---|
| 認証プロバイダー | Auth0(OAuth2) |
| Rails統合 | Devise + omniauth-auth0 + omniauth-rails_csrf_protection |
| ユーザー識別 | `auth0_uid`(テナントごとにユニーク) |
| テナントスコーピング | コールバック内でサブドメイン → テナント検索 |
| シードユーザーリンク | 初回ログイン時のメールベースマッチング |
| 新規ユーザーのデフォルトロール | `guest` |
| ロール管理 | Rails DBのみ（Auth0はロールに使わない） |
| シード管理者保護 | `seed_admin: true`でロール変更を防止 |
| パスワード保存 | なし。Auth0に完全委譲 |
| セッション管理 | Deviseのサーバーサイドセッション |
| ログインページ | `/dev_session/new` — Auth0ボタンまたは開発用ユーザー選択 |
| Turbo互換性 | Auth0ボタンはCORS問題を避けるため`data-turbo="false"`を使用 |
