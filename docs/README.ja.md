> 🇺🇸 [English version here](README.md)

# ドキュメント

このディレクトリには、マルチテナント タスク管理アプリの詳細な技術ドキュメントが含まれています。

プロジェクトの概要とクイックスタートガイドは [ルート README](../README.ja.md) を参照してください。

---

## ドキュメント一覧

| ドキュメント | 説明 |
|---|---|
| [design.ja.md](design.ja.md) | 設計ドキュメント — アーキテクチャ、データベーススキーマ、ルーティング、セキュリティレイヤーなど |
| [rls.ja.md](rls.ja.md) | PostgreSQL Row Level Security — 概念、RLS の仕組み、本プロジェクトでの実装 |
| [opa.ja.md](opa.ja.md) | Open Policy Agent — ポリシーベースの認可、Rego 言語、統合の詳細 |
| [auth0.ja.md](auth0.ja.md) | Auth0 認証 — OAuth2 フロー、Devise 統合、マルチテナント認証 |
| [testing.ja.md](testing.ja.md) | テスト — RSpec セットアップ、テスト構成、設計方針 |
| [ci.ja.md](ci.ja.md) | CI — GitHub Actions ワークフロー、各ジョブの目的、ローカル検証 |

---

## ダイアグラム

アーキテクチャとリクエストフローのダイアグラムは `docs/images/` に格納されています：

| ファイル | 説明 |
|---|---|
| [images/architecture.svg](images/architecture.svg) | システム全体のアーキテクチャ |
| [images/request_flow.svg](images/request_flow.svg) | リクエスト処理フロー |

---

## 推奨する読み順

このプロジェクトを初めて読む場合：

1. [ルート README](../README.ja.md) — プロジェクト概要とセットアップ
2. [design.ja.md](design.ja.md) — アーキテクチャと設計判断
3. [rls.ja.md](rls.ja.md) — データベース層のセキュリティの理解
4. [opa.ja.md](opa.ja.md) — 認可モデルの理解
5. [auth0.ja.md](auth0.ja.md) — 認証フローの理解
6. [testing.ja.md](testing.ja.md) — テスト戦略とテストの実行方法
7. [ci.ja.md](ci.ja.md) — CI パイプラインと自動品質チェック
