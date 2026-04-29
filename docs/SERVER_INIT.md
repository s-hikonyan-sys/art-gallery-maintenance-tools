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
| **Phase 0**: OS インストール後の手動作業 | ローカル WSL2 + さくらのVPS シリアルコンソール | `ssh-keygen`, `ssh-copy-id` |
| Phase 1: Ansible 実行 | ローカル WSL2 または GitHub Actions | `make server-init` |
| Phase 2: Secrets 更新 | GitHub | ブラウザ |
| Phase 3: アプリデプロイ | GitHub Actions | `art-gallery-release-tools` |

---

## Phase 0: OS インストール後の手動作業

Ansible を実行する前に、ローカル（WSL2）で SSH 鍵を用意し、VPS に登録する必要がある。

### 0-1. ローカル WSL2 で SSH 鍵を作成（初回のみ）

`alma` ユーザー接続用の鍵が**まだなければ**作成する。既存の鍵を使う場合はスキップ。

```bash
# Ed25519 鍵を作成（推奨）
ssh-keygen -t ed25519 -C "sakura-vps-init" -f ~/.ssh/sakura_init_key

# 作成された鍵を確認
ls -la ~/.ssh/sakura_init_key*
# sakura_init_key      ← 秘密鍵（絶対に外部に出さない）
# sakura_init_key.pub  ← 公開鍵（VPS に登録するもの）
```

> `server_init_vars.yml` の `init_ssh_key` にはこの秘密鍵のパス（`~/.ssh/sakura_init_key`）を設定する。

---

### 0-2. VPS 起動後の初回 SSH 接続確認

再起動が完了したら、パスワード認証で一度 `alma` ユーザーとしてログインできるか確認する。

```bash
# OS インストール後は known_hosts に古いホスト鍵が残っている場合があるのでクリア
ssh-keygen -R 219.94.248.165

# パスワードで接続テスト（インストール時に設定したパスワードを入力）
ssh alma@219.94.248.165
```

接続できたら `exit` で一度切断する。

---

### 0-3. ローカルの SSH 公開鍵を VPS に登録

`ssh-copy-id` を使って公開鍵を `alma` ユーザーの `authorized_keys` に登録する。

```bash
# 0-1 で作成した公開鍵を VPS に転送
ssh-copy-id -i ~/.ssh/sakura_init_key.pub alma@219.94.248.165

# 登録確認: 公開鍵認証で接続できるか確認
ssh -i ~/.ssh/sakura_init_key alma@219.94.248.165
```

> パスワードなしで接続できれば成功。以後の Ansible はこの鍵で接続する。

---

### 0-4. SSH ホスト鍵のフィンガープリントを確認（推奨）

中間者攻撃（MITM）防止のため、シリアルコンソールで取得したフィンガープリントと一致するか確認する。

```bash
# さくらのVPS シリアルコンソールから実行
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# 例: 256 SHA256:XXXXXXXXXX... no comment (ED25519)
```

```bash
# ローカルで接続時に表示されるフィンガープリントと一致するか確認してから yes を入力
ssh -i ~/.ssh/sakura_init_key alma@219.94.248.165
# The authenticity of host '219.94.248.165' can't be established.
# ED25519 key fingerprint is SHA256:XXXXXXXXXX...
# Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
```

参考: [さくらのVPS セキュリティ設定ガイド - SSH 接続でサーバーにログイン](https://manual.sakura.ad.jp/vps/support/security/firstsecurity.html)

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
- [x] **高リスク国ジオブロック**（[ipdeny.com](https://www.ipdeny.com/ipblocks/) の国別 IPv4 帯域を firewalld ipset に取り込み、**TCP 80 / 443 宛てのみ DROP**。SSH は対象外 → GitHub Actions からの SSH は阻害しない）
- [x] **Fail2ban**（`sshd` ジェイル有効。ブルートフォース試行を自動 BAN）
- [x] デプロイメントディレクトリ `/opt/art-gallery/` の作成
- [x] Let's Encrypt SSL 証明書の取得（`--skip-tags init-ssl` でスキップ可）
- [x] GHCR Docker 認証設定（`artgallery` ユーザー）

個別に再実行する場合の Ansible タグ例:

```bash
cd ansible
# ファイアウォール + ジオブロックのみ
ansible-playbook playbook_server_init.yml \
  --inventory inventory/production_init.yml \
  --extra-vars "@server_init_vars.yml" \
  --tags "init-firewall"

# Fail2ban のみ
ansible-playbook playbook_server_init.yml \
  --inventory inventory/production_init.yml \
  --extra-vars "@server_init_vars.yml" \
  --tags "init-fail2ban"
```

---

### 1-5. ジオブロックと Fail2ban の補足

#### ジオブロック（HTTP/HTTPS のみ）

| 項目 | 内容 |
|:---|:---|
| データソース | `https://www.ipdeny.com/ipblocks/data/countries/{国コード}.zone` |
| デフォルトでブロックする国 | `cn`, `ru`, `by`, `kp`, `ir`（`ansible/group_vars/all.yml` の `firewall_blocked_country_codes` で変更可） |
| 対象ポート | **TCP 80 と 443 のみ**（Web）。SSH (22) はブロックしない |
| 無効化 | `server_init_vars.yml` で `firewall_geo_block_enabled: false` を指定するか、リストを空にする |

**注意:**

- Let's Encrypt の HTTP-01 検証は主に米欧などの IP から行われる。本ジオブロックは上記の高リスク国の帯域のみを落とすため、通常は証明書更新に支障は出にくい。
- 海外在住の利用者や CDN 経由のアクセスがある場合は、国リストを見直すこと。
- IPv6 トラフィックは本プレイブックでは**未対応**（必要なら別途検討）。

#### Fail2ban

| 項目 | 内容 |
|:---|:---|
| 設定ファイル | `/etc/fail2ban/jail.d/99-art-gallery.local`（Ansible が生成） |
| デフォルト | `maxretry=5`, `findtime=600`, `bantime=3600`, `backend=systemd` |
| 自宅 IP の除外 | `server_init_vars.yml` で `fail2ban_ignore_ips: ["203.0.113.1/32"]` のように CIDR を列挙 |

動作確認:

```bash
sudo fail2ban-client status sshd
```

参考: [さくらのVPS セキュリティ設定ガイド](https://manual.sakura.ad.jp/vps/support/security/firstsecurity.html)

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

### ジオブロック（firewalld ipset）で Playbook が失敗する

- `firewall-cmd --permanent --add-entries-from-file` が古い firewalld では未サポートの場合がある。その場合は `firewall_geo_block_enabled: false` で無効化し、手動でルールを設計する。
- ipdeny.com への HTTPS 取得がタイムアウトする場合は、しばらく待ってから `--tags init-firewall` のみ再実行。

### Fail2ban が起動しない / sshd ジェイルが無効

```bash
sudo journalctl -u fail2ban -n 50 --no-pager
sudo fail2ban-client -d
```

AlmaLinux 10 で `backend=systemd` が合わない場合は、`ansible/roles/server_init/templates/99-art-gallery.local.j2` の `[sshd]` セクションを `backend = auto` に変更して再デプロイする。
