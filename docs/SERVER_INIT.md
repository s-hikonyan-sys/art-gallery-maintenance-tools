# 本番サーバー初期構築ガイド

OS 再インストール後に本番サーバーを復旧する手順書。

## 動作確認済み環境

| 項目 | 値 |
|:---|:---|
| OS | AlmaLinux 10.1 |
| さくらのVPS | v5 / SSD 50GB / 仮想2Core / 2GB メモリ |
| Ansible Playbook 接続ユーザー | `alma`（AlmaLinux 標準初期ユーザー） |

> 他のバージョンでも基本的に動作するが、AlmaLinux のバージョンが異なる場合は `ansible/roles/server_init/tasks/docker.yml` の `docker_repo_url` を確認すること。

---

## AlmaLinux 10 インストール時の注意事項

さくらのVPS のコントロールパネルから AlmaLinux 10 をインストールする際、インストーラーの「ユーザーの設定」画面で以下の点に注意すること。

- **`root` アカウントは有効化しない**（デフォルトで無効化されている状態を維持）
- **「ユーザーの作成(U)」で `alma` ユーザーを必ず作成する**  
  ユーザー名: `alma` / `wheel` グループに追加してsudo権限を付与
- SSH 公開鍵はコントロールパネルで登録するか、インストール後にシリアルコンソールから登録する

> `root` アカウントを無効のままにし、一般ユーザー `alma` + `sudo` で運用するのがさくらのVPS の推奨セキュリティ設定。  
> 参考: [さくらのVPS セキュリティ設定ガイド](https://manual.sakura.ad.jp/vps/support/security/firstsecurity.html)

---

## 概要

| フェーズ | 作業場所 | ツール |
|:---|:---|:---|
| Phase 1: Ansible 実行 | ローカル WSL2 または GitHub Actions | `make server-init` |
| Phase 2: Secrets 更新 | GitHub | ブラウザ |
| Phase 3: アプリデプロイ | GitHub Actions | `art-gallery-release-tools` |

---

## Phase 1: サーバー初期構築

### 1-1. 変数ファイルを作成

```bash
cd ansible
cp server_init_vars.yml.example server_init_vars.yml
nano server_init_vars.yml   # 各項目を設定
```

設定が必要な項目:

| 変数 | 内容 | 例 |
|:---|:---|:---|
| `init_host` | VPS の IP アドレス | `219.94.248.165` |
| `init_ssh_key` | AlmaLinux 初期ユーザー用 SSH 秘密鍵 | `~/.ssh/id_ed25519` |
| `deploy_ssh_public_key` | デプロイ用公開鍵（`PROD_SSH_PRIVATE_KEY` 対応） | `ssh-ed25519 AAAA...` |
| `certbot_email` | Let's Encrypt 通知メール | `you@example.com` |
| `ghcr_token` | GitHub PAT（`read:packages` スコープ） | `ghp_xxx...` |
| `ghcr_username` | GitHub ユーザー名 | `s-hikonyan-sys` |

> **`deploy_ssh_public_key` の確認方法**: `PROD_SSH_PRIVATE_KEY` に対応する公開鍵ファイル（`~/.ssh/xxx.pub` または `ssh-keygen -y -f ~/.ssh/xxx`）の内容を貼り付けてください。

### 1-2. Ansible collections をインストール

```bash
make install-ansible-collections
```

### 1-3. サーバー初期構築を実行

**DNS 設定済みの場合（SSL 証明書も取得）:**

```bash
make server-init
```

**DNS 未設定の場合（SSL は後で取得）:**

```bash
make server-init-no-ssl
# DNS 設定後に SSL のみ追加実行:
cd ansible && ansible-playbook playbook_server_init.yml \
  --inventory inventory/production_init.yml \
  --extra-vars "@server_init_vars.yml" \
  --tags "init-ssl"
```

### 1-4. 実行内容の確認

Playbook が完了すると以下が設定されます:

- [x] セキュリティアップデート適用
- [x] `artgallery` ユーザー作成（sudo 権限・SSH 公開鍵登録済み）
- [x] SSH パスワード認証の無効化
- [x] Docker CE + Docker Compose プラグインのインストール
- [x] firewalld の有効化（SSH / HTTP / HTTPS のみ許可）
- [x] デプロイメントディレクトリ `/opt/art-gallery/` の作成
- [x] Let's Encrypt SSL 証明書の取得（`--skip-tags init-ssl` でスキップ可）
- [x] GHCR Docker 認証設定（`artgallery` ユーザー）

---

## Phase 2: GitHub Secrets / Variables の更新

OS 再インストールで SSH ホスト鍵が変わるため **必ず更新が必要**。

### 2-1. 新しいホスト鍵を取得

```bash
make update-known-hosts
```

出力例:
```
219.94.248.165 ecdsa-sha2-nistp256 AAAA...
```

### 2-2. GitHub Secrets / Variables を更新

`art-gallery-release-tools` リポジトリの Settings → Secrets and variables:

| 名前 | 種別 | 更新内容 |
|:---|:---|:---|
| `PROD_SSH_KNOWN_HOSTS` | Secret | 2-1 で取得したホスト鍵で上書き |

必要に応じて以下も確認:

| 名前 | 種別 | 内容 |
|:---|:---|:---|
| `PROD_HOST` | Variable | VPS の IP（変わっていれば更新） |
| `PROD_SSH_USER` | Variable | `artgallery`（変わらなければ不要） |
| `PROD_SSH_PRIVATE_KEY` | Secret | デプロイ用秘密鍵（変わらなければ不要） |

---

## Phase 3: アプリデプロイ

`art-gallery-release-tools` の GitHub Actions を以下の順番で実行:

```
1. setup_startup_service.yml    → systemd 自動起動サービス設定
2. deploy_secrets.yml           → Secrets API デプロイ
3. deploy_database.yml          → DB デプロイ + マイグレーション
4. deploy_backend.yml           → Backend デプロイ
5. deploy_frontend.yml          → Frontend デプロイ
6. deploy_nginx.yml             → Nginx デプロイ
```

---

## トラブルシュート

### `alma` ユーザーで SSH 接続できない

```bash
# Sakura VPS のシリアルコンソールから接続して確認
ip addr show
# SSH サービス確認
systemctl status sshd
```

### Ansible 実行中に `UNREACHABLE` エラー

```bash
# SSH 接続を手動テスト
ssh -i ~/.ssh/id_ed25519 alma@219.94.248.165
# known_hosts をクリア（OS 再インストール後は必須）
ssh-keygen -R 219.94.248.165
```

### Docker インストールが失敗する

AlmaLinux 10 は比較的新しいため Docker の公式リポジトリが対応していない場合がある。

```bash
# リポジトリを手動確認
dnf repolist
# 代替: Podman で代替も可能
dnf install podman podman-docker
```

### SSL 証明書取得が失敗する

- DNS が VPS の IP アドレスに向いているか確認
- ポート 80 が firewalld で許可されているか確認
- Let's Encrypt のレート制限（1週間に5回まで）に引っかかっていないか確認

```bash
# ドライランでテスト
certbot certonly --standalone --dry-run -d nara-sketch.com
```
