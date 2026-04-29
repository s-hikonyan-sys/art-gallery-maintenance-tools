# art-gallery-maintenance-tools

art-gallery プロジェクトのローカル開発環境とメンテナンスツールを提供するリポジトリです。

## 概要

| ディレクトリ | 用途 |
|---|---|
| `local/` | WSL2 (Ubuntu) 上でのローカル開発環境（Docker Compose） |
| `ansible/` | 本番サーバー初期構築 Ansible Playbook |
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

### ローカル開発環境

シナリオ別の詳細な手順は [`docs/local_dev_guide.md`](docs/local_dev_guide.md) を参照してください。

- [シナリオA] フルスタック確認
- [シナリオB] バックエンドをローカルプロセスでデバッグ
- [シナリオC] フロントエンドを `npm run dev` でデバッグ

### 本番サーバー初期構築（OS 再インストール後）

OS 再インストール後の復旧手順は [`docs/SERVER_INIT.md`](docs/SERVER_INIT.md) を参照してください。

```bash
# 変数ファイルを作成・設定
cp ansible/server_init_vars.yml.example ansible/server_init_vars.yml
nano ansible/server_init_vars.yml

# サーバー初期構築実行（Docker / firewalld / 高リスク国ジオブロック HTTP(S) / Fail2ban / SSL 等）
# 完了後は SSH は ssh-admin のみ（alma は不可）。変数に admin_ssh_public_key が必要。
make server-init
```

初期構築後の検証テスト（pytest + testinfra）は [`docs/SERVER_VERIFY.md`](docs/SERVER_VERIFY.md) を参照してください。

## 前提条件

- Windows + WSL2 (Ubuntu)
- Docker Desktop（WSL2 backend）
- Python 3.11 以上（シナリオB でバックエンドをローカル起動する場合）
- Node.js 18 以上（シナリオC でフロントエンドをローカル起動する場合）
- 各リポジトリを `/home/<user>/` 以下にクローン済み（`/mnt/c/` は使用不可）
