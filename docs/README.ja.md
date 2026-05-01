> 🇺🇸 [English version here](README.md)

# ドキュメント

マルチテナント タスク管理アプリの技術ドキュメント置き場です。

プロジェクトの概要やセットアップ手順については[ルートREADME](../README.ja.md)を参照してください。


## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [design.ja.md](design.ja.md) | 設計ドキュメント。アーキテクチャ、DBスキーマ、ルーティング、セキュリティレイヤーなど |
| [rls.ja.md](rls.ja.md) | PostgreSQL Row Level Securityの概念と、本プロジェクトでの実装について |
| [opa.ja.md](opa.ja.md) | Open Policy Agentによるポリシーベース認可の仕組みと統合方法 |
| [auth0.ja.md](auth0.ja.md) | Auth0認証。OAuth2フロー、Deviseとの統合、マルチテナントでの認証 |
| [testing.ja.md](testing.ja.md) | テストまわり。RSpecのセットアップ、テスト構成、設計の考え方 |
| [ci.ja.md](ci.ja.md) | CI。GitHub Actionsのワークフロー構成、各ジョブの役割、ローカルでの検証方法 |


## ダイアグラム

アーキテクチャやリクエストフローの図は`docs/images/`に格納している。

| ファイル | 内容 |
|---|---|
| [images/architecture.ja.svg](images/architecture.ja.svg) | システム全体のアーキテクチャ |
| [images/request_flow.ja.svg](images/request_flow.ja.svg) | リクエスト処理フロー |


## 読む順番について

初めてこのプロジェクトを読む場合、以下の順番がわかりやすいかと思います。

1. [ルートREADME](../README.ja.md) — プロジェクト概要とセットアップ
2. [design.ja.md](design.ja.md) — アーキテクチャと設計判断
3. [rls.ja.md](rls.ja.md) — DB層のセキュリティ
4. [opa.ja.md](opa.ja.md) — 認可モデル
5. [auth0.ja.md](auth0.ja.md) — 認証フロー
6. [testing.ja.md](testing.ja.md) — テスト戦略と実行方法
7. [ci.ja.md](ci.ja.md) — CIパイプラインと自動チェック
