# マルチテナントのタスク管理アプリ(Rails Hotwire, RLS, OPA, Auth0)

B2B向けプロジェクト・タスク管理ツールのMVP。  
マルチテナント分離（アプリ層 + DB層）、OPAによるポリシーベース認可、Hotwireによるモダンな画面更新を特徴とする技術デモアプリケーションです。

## 主な特徴

- **多層テナント分離** — acts_as_tenant（アプリ層）+ PostgreSQL RLS（DB層）による二重防御
- **ポリシーベース認可** — Open Policy Agent (OPA) による外部化されたロールベースアクセス制御
- **SPA風UX** — Hotwire (Turbo Drive / Turbo Frames) によるリロード不要の画面更新
- **Auth0認証** — Devise + omniauth-auth0 によるOAuth2認証

## 技術スタック

| カテゴリ       | 技術                                                  |
| -------------- | ----------------------------------------------------- |
| バックエンド   | Ruby 3.4 / Rails 8.1                                  |
| データベース   | PostgreSQL 17 (RLS有効)                               |
| フロントエンド | Hotwire (Turbo Drive / Turbo Frames)                  |
| 認証           | Devise + omniauth-auth0                               |
| 認可           | Open Policy Agent (OPA)                               |
| マルチテナント | acts_as_tenant                                        |
| 開発環境       | DevContainer (Docker Compose)                         |
| CI             | GitHub Actions (Brakeman / RuboCop / importmap audit) |

## アーキテクチャ

```
Browser (Hotwire)  ──▶  Rails App (Puma)  ──▶  PostgreSQL (RLS有効)
                              │
                              ▼
                        OPA (Rego ポリシー)
```

### セキュリティレイヤー

| レイヤー             | 実装                                     |
| -------------------- | ---------------------------------------- |
| テナント識別         | サブドメイン方式 (`company-a.localhost`) |
| 認証                 | Devise + Auth0                           |
| アプリ層テナント分離 | acts_as_tenant (自動WHERE句)             |
| ロールベース認可     | OPA (admin / member / guest)             |
| DB層テナント分離     | PostgreSQL RLS (SET ROLE切り替え)        |

> 詳細な設計書は [docs/design.md](docs/design.md) を参照してください。

## 画面構成

| 画面             | パス                      | 説明                                     |
| ---------------- | ------------------------- | ---------------------------------------- |
| プロジェクト一覧 | `/projects`               | テナント内のプロジェクトを一覧表示       |
| タスク一覧       | `/projects/:id/tasks`     | タスク一覧。ステータスをその場で変更可能 |
| タスク詳細       | `/projects/:id/tasks/:id` | タスク詳細表示・ステータス変更           |

## セットアップ

### 前提条件

- [Docker](https://www.docker.com/) および [Docker Compose](https://docs.docker.com/compose/)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers 拡張](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)（推奨）

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd rails_hotwire_opa_tenant_manager
```

### 2. DevContainerの起動

VS Code でプロジェクトを開き、「Reopen in Container」を選択。  
以下の3サービスが起動します：

| サービス | ポート | 用途                  |
| -------- | ------ | --------------------- |
| app      | 8080   | Railsアプリケーション |
| db       | 5432   | PostgreSQL            |
| opa      | 8181   | OPAポリシーエンジン   |

### 3. データベースのセットアップ

```bash
bin/rails db:create db:migrate db:seed
```

### 4. Auth0の設定（任意）

Auth0を利用する場合、以下の環境変数を設定してください：

| 変数名                | 説明                          |
| --------------------- | ----------------------------- |
| `AUTH0_CLIENT_ID`     | Auth0クライアントID           |
| `AUTH0_CLIENT_SECRET` | Auth0クライアントシークレット |
| `AUTH0_DOMAIN`        | Auth0ドメイン                 |

> Auth0未設定の場合、development環境ではテナントの最初のユーザーで自動ログインします。

### 5. サーバーの起動

```bash
bin/rails server -b 0.0.0.0 -p 8080
```

ブラウザで以下にアクセス：

- `http://company-a.localhost:8080` — Company A のテナント
- `http://company-b.localhost:8080` — Company B のテナント

## シードデータ

| テナント  | サブドメイン | ユーザー                                            |
| --------- | ------------ | --------------------------------------------------- |
| Company A | company-a    | Admin A (admin), Member A (member), Guest A (guest) |
| Company B | company-b    | Admin B (admin)                                     |

## ドキュメント

- [詳細設計書](docs/design.md) — DB設計、RLS設計、OPA認可、Hotwire活用等の詳細

## ライセンス

このプロジェクトはポートフォリオ用の技術デモです。
