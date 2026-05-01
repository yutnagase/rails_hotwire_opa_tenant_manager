> 🇺🇸 [English version here](opa.md)

# Open Policy Agent (OPA) 認可

このドキュメントでは、Open Policy Agent とは何か、認可においてなぜ有用なのか、そして本プロジェクトでロールベースのアクセス制御をどのように実現しているかを説明します。



## Open Policy Agent とは？

Open Policy Agent (OPA) は、オープンソースの汎用ポリシーエンジンです。Rego と呼ばれる宣言型言語で記述されたポリシールールを評価し、認可判定（許可 / 拒否）を返します。

核心的なアイデア: ポリシーをアプリケーションコードから分離する。

コントローラ全体ロジックに `if user.admin?` チェックを入れることなく、全認可のルールを一箇所（Rego ファイル）に定義する
シンプルな HTTP APIロジックで、OPAによる認可ロジックを実装可能

```
アプリケーション  →  「member は taskテーブルに対して更新 できるか？」  →  OPA (Rego)  →  true / false
```



## OPA認可のメリット

| アプローチ | メリット | デメリット |
|---|---|---|
| アプリ内チェック (例: コントローラ内の `if/else`) | シンプル、追加サービス不要 | ルールがコードベース全体に散在、監査が困難 |
| OPA (外部化ポリシー) | ルールの一元管理、言語非依存、テスト可能 | 別サービスが必要 |

OPA が特に有効な場面：
- 認可ルールの単一の信頼できるソースが欲しい場合
- 全権限を 1 ファイルで監査・レビューしたい場合
- アプリケーションコードとは独立してポリシーをテストしたい場合
- 複数サービスで同じ認可ロジックを共有する必要がある場合



## 概要

### 1. Regoとは

Rego は OPA の宣言型ポリシー言語です。Rego ルールは全条件が満たされると `true` に評価されます：

例: 
```rego
allow if {
    input.user.role == "member"
    input.action in ["read", "create", "update"]
}
```

ユーザーのロールが `member` かつアクションが `read`, `create`, `update` のいずれかであれば許可する
と言う認可設定のロジック

### 2. Input

OPA は各リクエストで `input` と呼ばれる JSON オブジェクトを受け取る。
このJSON設定内でアプリケーションで認可の設定を入れる
例えば、ユーザーのロール、要求されたアクション、対象リソースなど

### 3. Decision

OPAは認可の全ルールに対して input を評価して、レスポンスとしてJSON オブジェクトを返す

```json
{ "result": true }   // 許可
{ "result": false }  // 拒否
```

### 4. デフォルト拒否

ポリシーは `default allow = false` とデフォルトは拒否ベースで定義する
これはルールが明示的に許可しない限り全てが拒否されることを想定している
セキュアバイデフォルトによるアプローチ



## 本プロジェクトのセキュリティモデルにおける OPA の位置づけ

本プロジェクトは多層セキュリティアーキテクチャを使用している
OPA は垂直方向のアクセス制御（テナント内でユーザーが何をできるか）を担当し、RLS と `acts_as_tenant` は水平方向の分離（テナント間のデータ分離）を担当

```
┌──────────────────────────────────────────────────┐
│  水平方向の分離（テナント間）                     │
│  acts_as_tenant + PostgreSQL RLS                 │
├──────────────────────────────────────────────────┤
│  垂直方向のアクセス制御（テナント内）             │
│  OPA — ロールベースの権限強制                    │
└──────────────────────────────────────────────────┘
```



## 本プロジェクトでの OPA 実装

### インフラ構成

OPA は Rails,PostgreSQL と同様にDocker コンテナとして実行される。
`docker-compose.yml` 内でopaコンテナを指定する

```yaml
# .devcontainer/docker-compose.yml
opa:
  image: openpolicyagent/opa:latest
  ports:
    - "8181:8181"
  command: ["run", "--server", "--addr", "0.0.0.0:8181", "/policies"]
  volumes:
    - ../opa/policy:/policies
```

Rego ポリシーファイル（`opa/policy/authz.rego`）がコンテナにマウントされる
また、OPA は起動時にロードして REST API で認可判定を実施する

### Rego ポリシー

本プロジェクトの完全な認可ポリシー：

```rego
# opa/policy/authz.rego
package authz

default allow = false

# admin: 全操作にフルアクセス
allow if input.user.role == "admin"

# member: 閲覧、作成、更新
allow if {
    input.user.role == "member"
    input.action in ["read", "create", "update"]
}

# guest: 閲覧のみ
allow if {
    input.user.role == "guest"
    input.action == "read"
}
```

権限マトリクス

| ロール \ アクション | read | create | update | delete |
|---|---|---|---|---|
| admin | ✅ | ✅ | ✅ | ✅ |
| member | ✅ | ✅ | ✅ | ❌ |
| guest | ✅ | ❌ | ❌ | ❌ |

### OPA クライアント

`OpaClient` は OPA に認可リクエストを送信するサービスクラス

```ruby
# app/services/opa_client.rb
class OpaClient
  OPA_URL = URI(ENV.fetch("OPA_URL", "http://opa:8181/v1/data/authz/allow"))

  def self.allowed?(user:, action:, resource:)
    payload = {
      input: {
        user: { role: user.role },
        action: action,
        resource: resource
      }
    }

    response = Net::HTTP.post(OPA_URL, payload.to_json, "Content-Type" => "application/json")
    JSON.parse(response.body).dig("result") == true
  rescue StandardError => e
    Rails.logger.error("[OPA] Request failed: #{e.message}")
    false  # フェイルセーフ: エラー時は拒否
  end
end
```

設計判断としては以下の方針
- フェイルセーフ — OPA に到達できない場合やエラーが返された場合、アクセスを拒否（`false`）
- 最小限の input — ユーザーのロール、アクション、リソースのみを送信。機密データはアプリ外に出さない
- 同期処理 — シンプルさのため `Net::HTTP.post` を使用。リクエストごとに 1 回呼び出し

### コントローラ統合

共通コントローラ(`ApplicationController`) の `before_action` にて全てのAPIリクエスト処理時に OPA を呼び出して認可制御する

```ruby
# app/controllers/application_controller.rb
before_action :authorize_with_opa

def authorize_with_opa
  return unless user_signed_in?

  opa_action = opa_action_for(action_name)
  resource = controller_name.singularize

  unless OpaClient.allowed?(user: current_user, action: opa_action, resource: resource)
    head :forbidden
  end
end
```

Rails コントローラアクションとOPA アクションの関係性

| Rails アクション | OPA アクション |
|---|---|
| `index`, `show` | `read` |
| `new`, `create` | `create` |
| `edit`, `update` | `update` |
| `destroy` | `delete` |

OPA が `false` を返した場合、コントローラは即座に HTTP 403 Forbidden を返し、以降の処理は行われない。

### リクエストフロー

```
1. ユーザーがリクエストを送信 (例: PATCH /projects/1/tasks/2)
2. ApplicationController がサブドメインからテナントを解決
3. Devise がユーザーを認証
4. authorize_with_opa が呼び出される:
   a. "update" アクション → OPA アクション "update" にマッピング
   b. "tasks" コントローラ → リソース "task" にマッピング
   c. OPA に送信:
      { "input": { "user": { "role": "member" }, "action": "update", "resource": "task" } }
   d. OPA が authz.rego を評価 → { "result": true } を返す
5. コントローラがアクションを続行
```

`guest` が `update` を試みた場合、OPA は `false` を返し、コントローラは 403 を返す。



## ロール

ロールは `users` テーブルの `role` カラムに保存され、ユーザー作成時に割り当て

| ロール | 想定用途 | 権限 |
|---|---|---|
| `admin` | テナント管理者 | 全操作 |
| `member` | 一般チームメンバー | 閲覧、作成、更新 |
| `guest` | 外部協力者 | 閲覧のみ |

Auth0 コールバックで作成される新規ユーザーにはデフォルトで `guest` ロールが割り当てられる。シード管理者ユーザーは `admin` ロールを保持し、変更不可（`seed_admin: true`）。



## ポリシーの追加・変更

認可ルールを変更するには `opa/policy/authz.rego` を編集。ファイルはボリュームマウントされているため、OPA は再起動時に変更を反映。

例 — プロジェクトのみ閲覧可能な `viewer` ロールの追加：

```rego
allow if {
    input.user.role == "viewer"
    input.action == "read"
    input.resource == "project"
}
```

アプリケーションコードの変更は不要
ここが、認可外出しの大きなメリット。



## まとめ

| 概念 | 本プロジェクトでの実装ポイント |
|---|---|
| ポリシーエンジン | ポート 8181 でDockerコンテナとして実行されるOPA |
| ポリシー言語 | Rego (`opa/policy/authz.rego`) |
| API エンドポイント | `http://opa:8181/v1/data/authz/allow` |
| クライアント | `OpaClient` (`app/services/opa_client.rb`) |
| コントローラフック | `ApplicationController` の `before_action :authorize_with_opa` |
| 障害時の動作 | フェイルセーフ — エラー時は拒否 |
| ロール | `admin`, `member`, `guest` (`users.role` に保存) |
| 関心事の分離 | OPA = 垂直（ロールベース）、RLS = 水平（テナントベース） |
