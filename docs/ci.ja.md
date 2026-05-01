> 🇺🇸 [English version here](ci.md)

# CI (継続的インテグレーション)

本プロジェクトでは GitHub Actions を使用して、コードチェック、脆弱性チェックなどを自動チェックする為CIを導入しています

CI は プッシュと`main`ブランチへのプルリクエスト作成時に自動実行されます



## CI とは？

CI (継続的インテグレーション) は、コード変更を頻繁に行う開発において、ソース管理リポジトリ上に配置して、変更時、自動テストとコードへの静的解析を実行する仕組みです

CI のメリット

- バグやセキュリティ問題の早期検出
- 一貫したコードスタイルの自動強制
- プルリクエストで確認できる客観的な「合格/不合格」ステータス
- コードが本番に到達する前の品質保証



## ワークフロー構成

CI 定義ファイルは [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) です。

5 つのジョブが並列実行されます

```
┌─────────────────────────────────────────────────┐
│              GitHub Actions CI                   │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ scan_ruby│  │ scan_js  │  │   lint   │       │
│  │(Brakeman)│  │(importmap│  │(RuboCop) │       │
│  │          │  │  audit)  │  │          │       │
│  └──────────┘  └──────────┘  └──────────┘       │
│                                                  │
│  ┌──────────┐  ┌──────────┐                      │
│  │   test   │  │ test_opa │                      │
│  │ (RSpec)  │  │(opa test)│                      │
│  └──────────┘  └──────────┘                      │
└─────────────────────────────────────────────────┘
```



## トリガー条件

```yaml
on:
  pull_request:
  push:
    branches: [ main ]
```

| イベント | 説明 |
|---|---|
| `push` to `main` | main ブランチに直接プッシュされた時に実行 |
| `pull_request` | プルリクエストが作成または更新された時に実行 |



## ジョブ詳細

### 1. scan_ruby — セキュリティ静的解析 (Brakeman)

| 項目 | 詳細 |
|---|---|
| ツール | [Brakeman](https://brakemanscanner.org/) |
| 目的 | 静的解析により Rails アプリケーションコードのセキュリティ脆弱性を検出 |
| 検出例 | SQL インジェクション、クロスサイトスクリプティング (XSS)、マスアサインメントなど |

仕組み

Brakemanは静的解析で、既知の脆弱性パターンに一致するコードを報告可能。データベースやサーバーなど不要

ローカル実行

```bash
bundle exec brakeman --no-pager
```

合格条件: `Security Warnings: 0`



### 2. scan_js — JavaScript 依存関係の脆弱性スキャン

| 項目 | 詳細 |
|---|---|
| ツール | [importmap audit](https://github.com/rails/importmap-rails) |
| 目的 | JavaScript 依存関係の既知の脆弱性をチェック |

仕組み

本プロジェクトは importmap-rails で JavaScript を管理している
`importmap audit` コマンド実行で `config/importmap.rb` で定義されたパッケージを脆弱性データベースと照合して脆弱性チェックしている

ローカル実行

```bash
bin/importmap audit
```

合格条件: 脆弱性の報告なし



### 3. lint — コードスタイルチェック (RuboCop)

| 項目 | 詳細 |
|---|---|
| ツール | [RuboCop](https://rubocop.org/) |
| 目的 | 一貫した Ruby コードスタイルと品質の強制 |
| 設定ファイル | [`.rubocop.yml`](../.rubocop.yml) |

仕組み

RuboCop はコーディング規約に対してソースコードを検査し、スタイル違反を報告。本プロジェクトでは `rubocop-rails-omakase`（Rails 公式推奨スタイル）をベースとして使用。

除外設定

`.rubocop.yml` は Ruby ファイルを含まない以下のディレクトリを除外

```yaml
AllCops:
  Exclude:
    - "opa//*"      # Rego ポリシーファイル
    - ".github//*"  # GitHub Actions ワークフロー (YAML)
```

CI 出力形式

CI では `-f github` オプションを使用。これにより GitHub のプルリクエスト差分ビューにインラインアノテーションとしてエラーが表示。

ローカル実行

```bash
bundle exec rubocop
```

合格条件: 違反ゼロ



### 4. test — アプリケーションテスト (RSpec)

| 項目 | 詳細 |
|---|---|
| ツール | [RSpec](https://rspec.info/) |
| 目的 | モデル、サービス、リクエストスペックの自動テスト |
| 必要なサービス | PostgreSQL (サービスコンテナ) |

仕組み

GitHub Actions の[サービスコンテナ](https://docs.github.com/ja/actions/using-containerized-services/about-service-containers)を使用してジョブ内でPostgreSQLを起動している。このDB環境にてテストを実施
テスト実行前に `db:create db:migrate` でテストDBを構築する必要がある

```yaml
services:
  postgres:
    image: postgres:17
    env:
      POSTGRES_PASSWORD: password
    ports:
      - 5432:5432
    options: >-
      --health-cmd="pg_isready -U postgres"
      --health-interval=5s
      --health-timeout=5s
      --health-retries=5
```

ポイント

- `options` の `--health-cmd` オプションにより、PostgreSQL が完全に準備できるまでジョブが待機
- OPA サービスコンテナは不要。テストコードは WebMock で OPA への HTTP リクエストをスタブ化している（詳細は [testing.ja.md](testing.ja.md) を参照）
- RLS用の `rails_user` ロールはマイグレーション中に自動作成されるため、追加のDB初期化は不要

環境変数

| 変数 | 値 | 説明 |
|---|---|---|
| `DB_HOST` | `localhost` | PostgreSQL サービスコンテナに接続 |
| `DB_SUPERUSER` | `postgres` | PostgreSQL スーパーユーザー |
| `DB_SUPERUSER_PASSWORD` | `password` | PostgreSQL パスワード |
| `RAILS_ENV` | `test` | Rails テスト環境を指定 |
| `OPA_URL` | `http://localhost:8181/...` | OPA URL（実際には WebMock でスタブ化） |

ローカル実行

```bash
bundle exec rspec
```

合格条件: 全テスト合格、失敗ゼロ

> テスト設計の詳細は [testing.ja.md](testing.ja.md) を参照。



### 5. test_opa — OPA ポリシーテスト

| 項目 | 詳細 |
|---|---|
| ツール | [OPA (Open Policy Agent)](https://www.openpolicyagent.org/) |
| 目的 | Rego で記述された認可ポリシーのユニットテスト |
| ポリシーファイル | [`opa/policy/authz.rego`](../opa/policy/authz.rego) |
| テストファイル | [`opa/policy/authz_test.rego`](../opa/policy/authz_test.rego) |

仕組み

OPA にはポリシーテスト機能が組み込まれている。`test_` プレフィックスを持つルールがテストケースとして認識され、`opa test` コマンドで実行。

CI では [open-policy-agent/setup-opa](https://github.com/open-policy-agent/setup-opa) アクションが OPA バイナリをインストールし、テストを実行。

テストケース（13 ケース）

| ロール | アクション | 期待結果 | テスト名 |
|---|---|---|---|
| admin | read | ✅ 許可 | `test_admin_allow_read` |
| admin | create | ✅ 許可 | `test_admin_allow_create` |
| admin | update | ✅ 許可 | `test_admin_allow_update` |
| admin | delete | ✅ 許可 | `test_admin_allow_delete` |
| member | read | ✅ 許可 | `test_member_allow_read` |
| member | create | ✅ 許可 | `test_member_allow_create` |
| member | update | ✅ 許可 | `test_member_allow_update` |
| member | delete | ❌ 拒否 | `test_member_deny_delete` |
| guest | read | ✅ 許可 | `test_guest_allow_read` |
| guest | create | ❌ 拒否 | `test_guest_deny_create` |
| guest | update | ❌ 拒否 | `test_guest_deny_update` |
| guest | delete | ❌ 拒否 | `test_guest_deny_delete` |
| unknown | read | ❌ 拒否 | `test_unknown_role_deny` |

OPA v1 構文

OPA v1 では `if` キーワードと `import rego.v1` が必要。ポリシーファイルとテストファイルの両方でこの構文を使用。

```rego
import rego.v1

test_admin_allow_read if { allow with input as {"user": {"role": "admin"}, "action": "read"} }
```

ローカル実行

```bash
docker exec -i $(docker ps -qf "ancestor=openpolicyagent/opa:latest") opa test /policies/ -v
```

合格条件: `PASS: 13/13`

> OPA 設計の詳細は [opa.ja.md](opa.ja.md) を参照。



## Dependabot — 自動依存関係更新

CI ジョブに加えて、[Dependabot](https://docs.github.com/ja/code-security/dependabot) を設定。

定義ファイルは [`.github/dependabot.yml`](../.github/dependabot.yml)。

| 対象 | チェック頻度 | 説明 |
|---|---|---|
| `bundler` | 毎日 | Ruby gem の新バージョンとセキュリティパッチを検出 |
| `github-actions` | 毎日 | GitHub Actions（例: `actions/checkout`）の更新を検出 |

Dependabot が更新を検出すると、自動的にプルリクエストを作成。その PR でも CI が実行されるため、更新による破壊的変更がマージ前に検出される。



## CI 結果の確認

### GitHub 上

1. リポジトリの Actions タブを開く
2. 該当するワークフロー実行をクリック
3. 各ジョブ名をクリックしてステップごとのログを確認

プルリクエスト内でもページ下部のChecksセクションで結果を確認できる

### ローカルでのプッシュ前検証

プッシュ前に全チェックをローカルで実行することを推奨

```bash
# RSpec (アプリケーションテスト)
bundle exec rspec

# OPA ポリシーテスト
docker exec -i $(docker ps -qf "ancestor=openpolicyagent/opa:latest") opa test /policies/ -v

# Brakeman (セキュリティスキャン)
bundle exec brakeman --no-pager

# RuboCop (コードスタイル)
bundle exec rubocop

# importmap audit (JS 依存関係スキャン)
bin/importmap audit
```



## ジョブサマリー

| ジョブ | ツール | カテゴリ | おおよその所要時間 |
|---|---|---|---|
| `scan_ruby` | Brakeman | セキュリティ | 約 30 秒 |
| `scan_js` | importmap audit | セキュリティ | 約 20 秒 |
| `lint` | RuboCop | コード品質 | 約 30 秒 |
| `test` | RSpec + PostgreSQL | テスト | 約 1-2 分 |
| `test_opa` | OPA | テスト | 約 20 秒 |

全ジョブが並列実行されるため、CI 全体の所要時間は最も遅いジョブ（通常は `test`）に依存。
