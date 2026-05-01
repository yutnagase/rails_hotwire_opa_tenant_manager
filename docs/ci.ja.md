> 🇺🇸 [English version here](ci.md)

# CI(継続的インテグレーション)

GitHub Actionsを使用して、コードチェックや脆弱性チェックなどを自動実行するCIを導入している。

プッシュ時と`main`ブランチへのPR作成時に自動実行される。



## CIとは

CI(継続的インテグレーション)は、コード変更のたびに自動テストや静的解析を実行する仕組みである。リポジトリに設定ファイルを配置しておけば、変更をpushするだけで自動的にチェックが走る。

CIを導入するメリットは以下の通り。

- バグやセキュリティ問題を早期に検出できる
- コードスタイルが自動的に統一される
- PRに「合格/不合格」のステータスが付くため判断しやすくなる
- 本番に出す前に品質を担保できる



## ワークフロー構成

CIの定義ファイルは[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)である。

5つのジョブが並列で実行される。

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

| イベント | 実行タイミング |
|---|---|
| `push` to `main` | mainに直接pushしたとき |
| `pull_request` | PRを作成または更新したとき |



## 各ジョブの詳細

### 1. scan_ruby — セキュリティ静的解析(Brakeman)

| 項目 | 詳細 |
|---|---|
| ツール | [Brakeman](https://brakemanscanner.org/) |
| 目的 | Railsコードのセキュリティ脆弱性を静的解析で検出する |
| 検出例 | SQLインジェクション、XSS、マスアサインメントなど |

Brakemanは静的解析のため、DBやサーバーがなくても実行可能である。既知の脆弱性パターンに一致するコードを検出して報告する。

ローカルでの実行方法

```bash
bundle exec brakeman --no-pager
```

合格条件: `Security Warnings: 0`



### 2. scan_js — JavaScript依存関係の脆弱性スキャン

| 項目 | 詳細 |
|---|---|
| ツール | [importmap audit](https://github.com/rails/importmap-rails) |
| 目的 | JS依存関係に既知の脆弱性がないかチェックする |

本プロジェクトはimportmap-railsでJSを管理しているため、`importmap audit`で`config/importmap.rb`のパッケージを脆弱性データベースと照合している。

ローカルでの実行方法

```bash
bin/importmap audit
```

合格条件: 脆弱性の報告なし



### 3. lint — コードスタイルチェック(RuboCop)

| 項目 | 詳細 |
|---|---|
| ツール | [RuboCop](https://rubocop.org/) |
| 目的 | Rubyコードのスタイルと品質を統一する |
| 設定ファイル | [`.rubocop.yml`](../.rubocop.yml) |

RuboCopがコーディング規約に沿っているかソースを検査し、違反があれば報告する。ベースは`rubocop-rails-omakase`（Rails公式推奨スタイル）を採用している。

除外設定

`.rubocop.yml`でRubyファイルを含まないディレクトリを除外している。

```yaml
AllCops:
  Exclude:
    - "opa//*"      # Regoポリシーファイル
    - ".github//*"  # GitHub Actionsワークフロー(YAML)
```

CIでは`-f github`オプションを付けており、PRの差分ビューにインラインでエラーが表示される。

ローカルでの実行方法

```bash
bundle exec rubocop
```

合格条件: 違反ゼロ



### 4. test — アプリケーションテスト(RSpec)

| 項目 | 詳細 |
|---|---|
| ツール | [RSpec](https://rspec.info/) |
| 目的 | モデル、サービス、リクエストスペックの自動テスト |
| 必要なサービス | PostgreSQL(サービスコンテナ) |

GitHub Actionsの[サービスコンテナ](https://docs.github.com/ja/actions/using-containerized-services/about-service-containers)でジョブ内にPostgreSQLを起動し、そこでテストを実行する。テスト前に`db:create db:migrate`でテストDBを構築する必要がある。

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

ポイントとしては以下の通り。
- `--health-cmd`によりPostgreSQLが完全に起動するまでジョブが待機する
- OPAのサービスコンテナは不要。テストではWebMockでOPAへのHTTPリクエストをスタブ化している（詳しくは[testing.ja.md](testing.ja.md)を参照）
- RLS用の`rails_user`ロールはマイグレーション中に自動作成されるため、追加のDB初期化は不要である

環境変数

| 変数 | 値 | 説明 |
|---|---|---|
| `DB_HOST` | `localhost` | PostgreSQLサービスコンテナへの接続先 |
| `DB_SUPERUSER` | `postgres` | PostgreSQLスーパーユーザー |
| `DB_SUPERUSER_PASSWORD` | `password` | PostgreSQLパスワード |
| `RAILS_ENV` | `test` | Railsテスト環境 |
| `OPA_URL` | `http://localhost:8181/...` | OPA URL（実際はWebMockでスタブ化） |

ローカルでの実行方法

```bash
bundle exec rspec
```

合格条件: 全テスト合格

> テスト設計の詳細は[testing.ja.md](testing.ja.md)を参照。



### 5. test_opa — OPAポリシーテスト

| 項目 | 詳細 |
|---|---|
| ツール | [OPA(Open Policy Agent)](https://www.openpolicyagent.org/) |
| 目的 | Regoで記述した認可ポリシーのユニットテスト |
| ポリシーファイル | [`opa/policy/authz.rego`](../opa/policy/authz.rego) |
| テストファイル | [`opa/policy/authz_test.rego`](../opa/policy/authz_test.rego) |

OPAにはポリシーテスト機能が組み込まれており、`test_`プレフィックスのルールがテストケースとして認識される。`opa test`コマンドで実行する。

CIでは[open-policy-agent/setup-opa](https://github.com/open-policy-agent/setup-opa)アクションでOPAバイナリをインストールしてテストを実行している。

テストケース（13ケース）

| ロール | アクション | 期待結果 | テスト名 |
|---|---|---|---|
| admin | read | 許可 | `test_admin_allow_read` |
| admin | create | 許可 | `test_admin_allow_create` |
| admin | update | 許可 | `test_admin_allow_update` |
| admin | delete | 許可 | `test_admin_allow_delete` |
| member | read | 許可 | `test_member_allow_read` |
| member | create | 許可 | `test_member_allow_create` |
| member | update | 許可 | `test_member_allow_update` |
| member | delete | 拒否 | `test_member_deny_delete` |
| guest | read | 許可 | `test_guest_allow_read` |
| guest | create | 拒否 | `test_guest_deny_create` |
| guest | update | 拒否 | `test_guest_deny_update` |
| guest | delete | 拒否 | `test_guest_deny_delete` |
| unknown | read | 拒否 | `test_unknown_role_deny` |

OPA v1では`if`キーワードと`import rego.v1`が必要となった。ポリシーファイルもテストファイルもこの構文で記述している。

```rego
import rego.v1

test_admin_allow_read if { allow with input as {"user": {"role": "admin"}, "action": "read"} }
```

ローカルでの実行方法

```bash
docker exec -i $(docker ps -qf "ancestor=openpolicyagent/opa:latest") opa test /policies/ -v
```

合格条件: `PASS: 13/13`

> OPAの設計については[opa.ja.md](opa.ja.md)を参照。



## Dependabot — 依存関係の自動更新

CIジョブとは別に、[Dependabot](https://docs.github.com/ja/code-security/dependabot)も設定している。

定義ファイルは[`.github/dependabot.yml`](../.github/dependabot.yml)である。

| 対象 | チェック頻度 | 内容 |
|---|---|---|
| `bundler` | 毎日 | Ruby gemの新バージョンやセキュリティパッチを検出 |
| `github-actions` | 毎日 | GitHub Actions（`actions/checkout`など）の更新を検出 |

更新が見つかるとDependabotが自動でPRを作成する。そのPRでもCIが実行されるため、破壊的変更があればマージ前に検出される。



## CI結果の確認方法

### GitHub上での確認

1. リポジトリのActionsタブを開く
2. 該当するワークフロー実行をクリック
3. 各ジョブ名をクリックするとステップごとのログを確認できる

PRのページ下部にあるChecksセクションでも結果を確認可能である。

### ローカルでの事前検証

push前に一通りローカルで実行しておくことを推奨する。

```bash
# RSpec
bundle exec rspec

# OPAポリシーテスト
docker exec -i $(docker ps -qf "ancestor=openpolicyagent/opa:latest") opa test /policies/ -v

# Brakeman
bundle exec brakeman --no-pager

# RuboCop
bundle exec rubocop

# importmap audit
bin/importmap audit
```



## ジョブサマリー

| ジョブ | ツール | カテゴリ | 所要時間の目安 |
|---|---|---|---|
| `scan_ruby` | Brakeman | セキュリティ | 約30秒 |
| `scan_js` | importmap audit | セキュリティ | 約20秒 |
| `lint` | RuboCop | コード品質 | 約30秒 |
| `test` | RSpec + PostgreSQL | テスト | 約1〜2分 |
| `test_opa` | OPA | テスト | 約20秒 |

全ジョブが並列実行されるため、CI全体の所要時間は最も遅いジョブ（通常は`test`）に依存する。
