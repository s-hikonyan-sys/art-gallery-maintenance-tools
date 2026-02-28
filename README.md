# art-gallery-maintenance-tools

art-gallery プロジェクトのローカル開発環境とメンテナンスツールを提供するリポジトリです。

## 概要

| ディレクトリ | 用途 |
|---|---|
| `local/` | WSL2 (Ubuntu) 上でのローカル開発環境（Docker Compose） |
| `maintenance/` | 本番メンテナンス用 Ansible タスク（将来追加予定） |
| `docs/` | 手順書・ドキュメント |

## クイックスタート

```bash
# 1. セットアップ（初回のみ）
make setup

# 2. .env を編集して各リポジトリのパスと GHCR_TOKEN を設定
nano local/.env

# 3. 開発用シークレット生成（初回のみ）
make gen-secrets

# 4. GHCR にログイン（初回のみ）
make ghcr-login

# 5. インフラを起動
make start-infra
```

## 起動コマンド

| コマンド | 起動コンテナ | 用途 |
|---|---|---|
| `make start-infra` | secrets-api, postgres | バックエンドをローカルプロセスでデバッグ |
| `make start-dev-frontend` | secrets-api, postgres, backend | フロントエンドを `npm run dev` でデバッグ |
| `make start-full` | 全コンテナ | 本番構成に近い形での動作確認 |

## 詳細手順

シナリオ別の詳細な手順は [`docs/local_dev_guide.md`](docs/local_dev_guide.md) を参照してください。

- [シナリオA] フルスタック確認
- [シナリオB] バックエンドをローカルプロセスでデバッグ
- [シナリオC] フロントエンドを `npm run dev` でデバッグ

## 前提条件

- Windows + WSL2 (Ubuntu)
- Docker Desktop（WSL2 backend）
- Python 3.11 以上（シナリオB でバックエンドをローカル起動する場合）
- Node.js 18 以上（シナリオC でフロントエンドをローカル起動する場合）
- 各リポジトリを `/home/<user>/` 以下にクローン済み（`/mnt/c/` は使用不可）
