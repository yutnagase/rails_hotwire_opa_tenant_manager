> 🇺🇸 [English version here](README.md)

# マルチテナント タスク管理アプリ (Rails, Hotwire, RLS, OPA, Auth0)

Ruby on Rails で構築された **B2B 向けプロジェクト・タスク管理 MVP** です。  
マルチテナントのデータ分離、OPA によるポリシーベースの認可、Hotwire を活用したモダンな UI を紹介する**技術デモプロジェクト**です。

機能は意図的に最小限に抑えていますが、**アーキテクチャ、セキュリティ、説明可能性**に重点を置いており、学習・実験・ポートフォリオ用途に適しています。



## 主な特徴

- **多層テナント分離**  
  アプリケーション層の `acts_as_tenant` と、データベース層の **PostgreSQL Row Level Security (RLS)** による二重保護。

- **ポリシーベースの認可**  
  ロールベースのアクセス制御を **Open Policy Agent (OPA)** に外部化し、コントローラから認可ルールを分離。

- **SPA ライクなユーザー体験**  
  Hotwire (Turbo Drive / Turbo Frames) により、フルページリロードなしのシームレスな UI 更新を実現。

- **Auth0 認証**  
  認証を Auth0 (Devise + OmniAuth) に委譲。  
  Auth0 は本人確認のみを担当し、ロール管理は Rails 内で完結。



## 技術スタック

| カテゴリ       | 技術                                                  |
| -------------- | ----------------------------------------------------- |
| バックエンド   | Ruby 3.4 / Rails 8.1                                  |
| データベース   | PostgreSQL 17 (RLS 有効)                               |
| フロントエンド | Hotwire (Turbo Drive / Turbo Frames)                  |
| 認証           | Devise + omniauth-auth0                               |
| 認可           | Open Policy Agent (OPA)                               |
| マルチテナンシー | acts_as_tenant                                      |
| テスト         | RSpec, FactoryBot, shoulda-matchers, WebMock          |
| 開発環境       | DevContainer (Docker Compose)                         |
| CI             | GitHub Actions (RSpec / OPA ポリシーテスト / Brakeman / RuboCop / Importmap audit) |



## アーキテクチャ概要

```
ブラウザ (Hotwire)
        │
        ▼
Rails アプリケーション (Puma)
        │
        ├── 認可判定 → OPA (Rego ポリシー)
        │
        ▼
PostgreSQL (Row Level Security 有効)
```



## セキュリティレイヤー

| レイヤー               | 実装                                    |
| ---------------------- | --------------------------------------- |
| テナント識別           | サブドメインベース (`company-a.localhost`) |
| 認証                   | Devise + Auth0                          |
| アプリ層の分離         | acts_as_tenant (自動スコーピング)        |
| ロールベースの認可     | OPA (admin / member / guest)            |
| DB 層の分離            | PostgreSQL RLS (`SET ROLE`)             |

> 詳細なドキュメントは [docs/](docs/README.ja.md) ディレクトリを参照してください。



## 画面 / ルーティング

| 画面           | パス                      | 説明                                 |
| -------------- | ------------------------- | ------------------------------------ |
| プロジェクト一覧 | `/projects`             | テナント内の全プロジェクトを一覧表示 |
| タスク一覧     | `/projects/:id/tasks`     | インラインステータス更新付きタスク一覧 |
| タスク詳細     | `/projects/:id/tasks/:id` | タスク詳細とステータス更新           |



## セットアップ

### 前提条件

- [Docker](https://www.docker.com/) および [Docker Compose](https://docs.docker.com/compose/)
- [Visual Studio Code](https://code.visualstudio.com/) と
  [Dev Containers 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (推奨)



### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd rails_hotwire_opa_tenant_manager
```



### 2. Dev Container の起動

VS Code でプロジェクトを開き、**Reopen in Container** を選択します。

以下のサービスが起動します：

| サービス | ポート | 用途              |
| -------- | ------ | ----------------- |
| app      | 8080   | Rails アプリケーション |
| db       | 5432   | PostgreSQL        |
| opa      | 8181   | OPA ポリシーエンジン |

> `bundle install` はコンテナ作成時に自動実行されます（`devcontainer.json` の `postCreateCommand`）。手動での gem インストールは不要です。



### 3. データベースセットアップ

Dev Container 内で：

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```



### 4. Auth0 と環境変数の設定

`.devcontainer/.env` を以下の変数で作成します：

| 変数                        | 説明                                     |
| --------------------------- | ---------------------------------------- |
| AUTH0_CLIENT_ID             | Auth0 アプリケーションのクライアント ID  |
| AUTH0_CLIENT_SECRET         | Auth0 アプリケーションのクライアントシークレット |
| AUTH0_DOMAIN                | Auth0 テナントドメイン                   |
| SEED_ADMIN_EMAIL_COMPANY_A  | Company A 初期管理者のメールアドレス     |
| SEED_ADMIN_EMAIL_COMPANY_B  | Company B 初期管理者のメールアドレス     |

シード管理者のメールアドレスは、初期管理者がログインに使用する Google アカウント（または他の Auth0 ID プロバイダー）のメールアドレスと一致する必要があります。

> Auth0 が未設定の場合、開発専用のユーザー選択画面が表示されます。



### 5. Rails サーバーの起動

```bash
bin/rails server -b 0.0.0.0 -p 8080
```



### 6. テストの実行

Dev Container 内で：

```bash
# RSpec
bundle exec rspec

# OPA ポリシーテスト
docker exec -i $(docker ps -qf "ancestor=openpolicyagent/opa:latest") opa test /policies/ -v

# Brakeman
bundle exec brakeman --no-pager

# RuboCop
bundle exec rubocop

# Importmap audit
bin/importmap audit
```

> テスト構成と設計の詳細は [docs/testing.ja.md](docs/testing.ja.md) を参照してください。

サブドメインでアプリケーションにアクセスします：

- `http://company-a.localhost:8080` — Company A テナント
- `http://company-b.localhost:8080` — Company B テナント



## シードデータ

| テナント  | サブドメイン | ユーザー        |
| --------- | ------------ | --------------- |
| Company A | company-a    | Admin A (admin) |
| Company B | company-b    | Admin B (admin) |

シード管理者ユーザーは `seed_admin: true` で作成され、ロールの変更はできません。  
追加ユーザーは Auth0 初回ログイン時に `guest` として自動作成され、管理者がロールを変更できます。



## 学習・設計の重点

このプロジェクトは以下に意図的にフォーカスしています：

- PostgreSQL RLS の正確で安全な使用方法
- OPA による認可関心事の分離
- コントローラと結合しないロールベースのアクセス制御
- `SET ROLE` 使用時のデータベースコネクションプーリングの安全な取り扱い
- Dev Container による再現可能なローカル開発環境

アーキテクチャを理解しやすくするため、機能スコープは意図的に小さく保っています。



## 今後の改善予定

- テナント内ユーザーロール管理の管理画面
- OPA を使用したトークンベースの API 認可



## 免責事項

このプロジェクトは**学習・ポートフォリオ向けの技術デモ**です。

- Auth0 の本番設定は含まれていません
- セキュリティレビューなしでの本番利用は想定していません



## ライセンス

[MIT License](LICENSE)
