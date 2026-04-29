# 本番サーバー初期構築ガイド

OS 再インストール後に本番サーバーを復旧する手順書。

## 動作確認済み環境

| 項目 | 値 |
|:---|:---|
| OS | AlmaLinux 10.1 |
| さくらのVPS | v5 / SSD 50GB / 仮想2Core / 2GB メモリ |
| 初回 Ansible 接続ユーザー | `alma`（AlmaLinux 標準初期ユーザー） |
| Playbook 完了後の SSH 接続ユーザー | `ssh-admin`（`AllowUsers` により `alma` は SSH 不可） |

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
| Phase 1: Ansible 実行（`alma` で接続 → 末尾で SSH を `ssh-admin` のみに制限） | ローカル WSL2 または GitHub Actions | `make server-init` |
| Phase 2: Secrets 更新 | GitHub | ブラウザ |
| Phase 3: アプリデプロイ | GitHub Actions | `art-gallery-release-tools` |

---

## Phase 0: OS インストール後の手動作業

Ansible を実行する前に、ローカル（WSL2）で SSH 鍵を用意し、VPS に登録する必要がある。

> 以降のコマンド例に出てくる `YOUR_VPS_GLOBAL_IP` は、対象 VPS のグローバル IPv4（さくらのVPS コントロールパネル「基本情報」に表示される値）に置き換えること。

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
ssh-keygen -R YOUR_VPS_GLOBAL_IP

# パスワードで接続テスト（インストール時に設定したパスワードを入力）
ssh alma@YOUR_VPS_GLOBAL_IP
```

接続できたら `exit` で一度切断する。

---

### 0-2a. さくらVPS パケットフィルターの推奨運用

さくらVPS のパケットフィルター（コントロールパネル側）と、OS 内の firewalld は**別レイヤー**。  
初期化中は次の順序で開放すると安全かつ詰まりにくい。

1. **OS 作成直後（Ansible 実行前）**  
   - 最小開放: `SSH(22)` のみ  
   - 可能なら送信元を自宅 IP / 作業元 IP に限定
2. **`init-ssl` を実行する直前**  
   - `HTTP(80)` と `HTTPS(443)` を追加で開放  
   - `certbot certonly --standalone` の HTTP-01 検証で `80` が必須
3. **Ansible 完了後の通常運用**  
   - `22/80/443` を維持（SSH は必要に応じて送信元制限）

> 80 番を開け忘れると、Let's Encrypt 検証で `Timeout during connect (likely firewall problem)` になりやすい。

---

### 0-3. ローカルの SSH 公開鍵を VPS に登録

`ssh-copy-id` を使って公開鍵を `alma` ユーザーの `authorized_keys` に登録する。

```bash
# 0-1 で作成した公開鍵を VPS に転送
ssh-copy-id -i ~/.ssh/sakura_init_key.pub alma@YOUR_VPS_GLOBAL_IP

# 登録確認: 公開鍵認証で接続できるか確認
ssh -i ~/.ssh/sakura_init_key alma@YOUR_VPS_GLOBAL_IP
```

> **成功の目安:** `alma` ユーザーの**ログインパスワード**（パスワード認証）は求められず、公開鍵だけでログインできること。Phase 1 の Ansible はこの鍵で **`alma` として**接続する（完了後は `ssh-admin` のみが SSH 可能になる）。
>
> **鍵のパスフレーズについて:** 0-1 で秘密鍵にパスフレーズを付けた場合、`Enter passphrase for key '.../sakura_init_key':` のように**鍵のパスフレーズ**を聞かれるのは正常である（VPS 側のパスワード認証とは別）。毎回の入力を減らすには `eval "$(ssh-agent -s)"` のあと `ssh-add ~/.ssh/sakura_init_key` でエージェントに載せる。

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
ssh -i ~/.ssh/sakura_init_key alma@YOUR_VPS_GLOBAL_IP
# The authenticity of host 'YOUR_VPS_GLOBAL_IP' can't be established.
# ED25519 key fingerprint is SHA256:XXXXXXXXXX...
# Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
```

参考: [さくらのVPS セキュリティ設定ガイド - SSH 接続でサーバーにログイン](https://manual.sakura.ad.jp/vps/support/security/firstsecurity.html)

### Phase 0 と Phase 1 のユーザー整理

| 段階 | SSH でログインするユーザー | 用途 |
|:---|:---|:---|
| Phase 0（手動） | `alma` | 公開鍵登録まで。OS インストール時に作成したユーザー |
| Phase 1（Ansible 実行中） | `alma`（inventory の `ansible_user`） | 初回構築プレイブックは `alma` で接続する |
| Phase 1 完了後 | `ssh-admin` のみ | `AllowUsers ssh-admin` により `alma`・`artgallery` などは **SSH ログイン不可**（`artgallery` はデプロイ専用） |
| デプロイ（release-tools / GitHub Actions） | `ssh-admin`（`PROD_SSH_USER`） | `inventory/production.yml` の `prod_ssh_user` と一致させる |

`ssh-admin` は Playbook 内で作成され、**`admin_ssh_public_key`** に指定した公開鍵でログインする。多くの場合、0-3 で `alma` に登録した `sakura_init_key.pub` の1行と同じ内容を `server_init_vars.yml` に書けば、同じ秘密鍵で `ssh-admin` に接続できる。

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
| `init_host` | VPS の IP アドレス | `YOUR_VPS_GLOBAL_IP` |
| `init_ssh_key` | AlmaLinux 初期ユーザー用 SSH 秘密鍵 | `~/.ssh/sakura_init_key` |
| `admin_ssh_public_key` | `ssh-admin` に登録する公開鍵の1行（通常は `sakura_init_key.pub` と同じ） | `ssh-ed25519 AAAA...` |
| `deploy_ssh_public_key` | デプロイ用公開鍵（`PROD_SSH_PRIVATE_KEY` 対応・`artgallery` ユーザー） | `ssh-ed25519 AAAA...` |
| `domain_name` | SSL 証明書発行対象ドメイン（`init-ssl` で利用） | `example.com` |
| `certbot_email` | Let's Encrypt 通知メール | `you@example.com` |
| `ghcr_token` | GitHub PAT（本運用は push + pull 前提） | `ghp_xxx...` |
| `ghcr_username` | GitHub ユーザー名 | `s-hikonyan-sys` |

**ローカル実行時の切り分け（重要）**

- **実行前に手元で設定が必要**: `init_host`, `init_ssh_key`, `admin_ssh_public_key`, `deploy_ssh_public_key`, `domain_name`, `certbot_email`, `ghcr_token`, `ghcr_username`
- **この時点では未作成でOK（Playbook がサーバー側に作る）**: `ssh-admin` ユーザー、`artgallery` ユーザー、各 `authorized_keys`、`AllowUsers ssh-admin`
- **ローカル実行後に期待される状態**: `ssh-admin` で SSH 可能、`alma` は SSH 不可、`artgallery` はデプロイ専用（SSH 不可）

> **`admin_ssh_public_key` の確認方法**: 0-1〜0-3 で使った公開鍵ファイルの内容をそのまま貼る（例: `cat ~/.ssh/sakura_init_key.pub`）。**`init_ssh_key` に対応する公開鍵と一致**させないと、Playbook 完了後に `ssh-admin` でログインできず詰む。
>
> **`deploy_ssh_public_key` の確認方法**: `PROD_SSH_PRIVATE_KEY` に対応する公開鍵（`~/.ssh/xxx.pub` または `ssh-keygen -y -f ~/.ssh/xxx`）。GitHub Actions が `artgallery` に接続する鍵であり、管理用の `sakura_init_key` と別でもよい。

> **`domain_name` の設定**: `init-ssl` が `certbot certonly --standalone -d <domain>` を実行するときの対象ドメイン。`example.com` はサンプルなので、実行時は実運用ドメインに置き換える。

> **GitHub Actions 実行時との違い**: `.github/workflows/server_init.yml` では `server_init_vars.yml` をワークフロー内で生成し、`init_host`・`domain_name` などを Variables/Secrets から注入する。`admin_ssh_public_key` も `INIT_SSH_PRIVATE_KEY` から自動算出される。
>
> **PAT 補足（fine-grained を使う場合）**: `Repository access` は `Only select repositories` を推奨し、GHCR の push/pull 対象リポジトリのみを選択する。`Tokens (classic)` には `Repository access` 設定はない。
>
> **対象リポジトリの考え方**: `art-gallery-release-tools` は workflow 実行元として必須。`art-gallery-backend` / `art-gallery-database` / `art-gallery-secrets` / `art-gallery-nginx`（+ `art-gallery-nginx-base`）は、GitHub ソース参照と GHCR イメージ運用の対象として選択する。詳細は `docs/SECURITY_ROTATION_RUNBOOK.md` を参照。
>
> **初回実行と運用実行の切り分け（接続ユーザー）**: 接続ユーザーは `ansible/vars/connection_bootstrap.yml`（初回=`alma`）と `ansible/vars/connection_operations.yml`（運用=`ssh-admin`）で分離している。

#### `deploy_ssh_public_key` を管理鍵と分離する手順（推奨）

`sakura_init_key`（管理用）とは別に、`artgallery` デプロイ専用鍵を作って運用できる。

```bash
# 1) デプロイ専用鍵を新規作成（既存の管理鍵とは別ファイル）
ssh-keygen -t ed25519 -C "artgallery-deploy-key" -f ~/.ssh/artgallery_deploy_key

# 2) 公開鍵を server_init_vars.yml に設定するため内容を取得
cat ~/.ssh/artgallery_deploy_key.pub
```

`server_init_vars.yml` には以下のように設定する:

```yaml
deploy_ssh_public_key: "ssh-ed25519 AAAA... artgallery-deploy-key"
```

Playbook 実行後、GitHub Actions でデプロイするには `art-gallery-release-tools` 側の `PROD_SSH_PRIVATE_KEY` を **同じ鍵ペアの秘密鍵**（`~/.ssh/artgallery_deploy_key` の内容）に更新する。

```bash
# 秘密鍵の内容をコピーして GitHub Secret に登録
cat ~/.ssh/artgallery_deploy_key
```

> 注意: `deploy_ssh_public_key` と `PROD_SSH_PRIVATE_KEY` は必ず同一鍵ペアで揃えること。ずれるとデプロイ時に SSH 認証で失敗する。

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
  --extra-vars "@vars/connection_operations.yml" \
  --tags "init-ssl"
```

### 1-3b. SSL（`init-ssl`）の前提チェック

`init-ssl` は `certbot certonly --standalone` で証明書を取得するため、実行前に以下を満たしている必要がある。

- ドメインの A レコードが `YOUR_VPS_GLOBAL_IP` を向いている
- 80/443 が firewalld で許可されている（本 Playbook デフォルトは許可）
- さくらVPS パケットフィルターでも 80/443 が開放されている
- `certbot_email` が `server_init_vars.yml` に設定済み

確認例:

```bash
# ローカルで DNS を確認
dig +short example.com
nslookup example.com
```

> 注: `example.com` はサンプル。実行時はあなたの実ドメイン（例: `your-domain.example`）に置き換えること。

### 1-3a. 完了後の SSH 確認（推奨）

Playbook が成功したら、**別のターミナル**で `ssh-admin` 接続を試す（既存の `alma` セッションは維持されることが多いが、設定誤りのときの保険になる）。

```bash
ssh -i ~/.ssh/sakura_init_key ssh-admin@YOUR_VPS_GLOBAL_IP
```

問題なければ `alma` への SSH は拒否される（`Permission denied`）ことを確認してよい。

### 1-3c. SSL 適用後の確認（推奨）

```bash
# ローカルで HTTPS 応答確認
curl -I https://example.com

# サーバー側で証明書確認（ssh-admin で接続後）
sudo certbot certificates
sudo certbot renew --dry-run
sudo systemctl status snap.certbot.renew.timer
```

> 注: 上記 `example.com` は説明用の仮ドメイン。実行時は実ドメインへ置き換える。

SSL の詳細運用（手動実行手順、失敗時の切り分け）は `docs/SSL_OPERATION.md` を参照。

### 1-4. 実行内容の確認

Playbook が完了すると以下が設定されます:

- [x] セキュリティアップデート適用
- [x] **`ssh-admin` ユーザー作成**（wheel・sudo NOPASSWD・`admin_ssh_public_key` 登録・docker グループ）
- [x] `artgallery` ユーザー作成（sudo 権限・デプロイ用 SSH 公開鍵登録済み。**AllowUsers により SSH ログインは不可**）
- [x] **SSH 強制**（`PermitRootLogin no`・パスワード認証無効・**`AllowUsers ssh-admin` のみ** → `alma` は SSH 不可）
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

`--tags` で部分実行する場合、`init-ssh-lockdown` を含めない限り **`AllowUsers ssh-admin` は再適用されない**（既にロック済みのサーバーでは通常問題ない）。**初回フル実行以外で `init-ssh-lockdown` だけを単独実行すると、`ssh-admin` が未作成のときに接続不能になる**ので避けること。

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
YOUR_VPS_GLOBAL_IP ecdsa-sha2-nistp256 AAAA...
```

### 2-2. GitHub Secrets / Variables を更新

まず、`art-gallery-maintenance-tools` リポジトリ（`server_init` workflow 用）で以下を定義/確認する:

| 名前 | 種別 | 内容 |
|:---|:---|:---|
| `PROD_HOST` | Variable | 初期化対象 VPS の IP（`server_init` の接続先） |
| `PROD_DOMAIN_NAME` | Variable | SSL 証明書発行対象ドメイン |
| `CERTBOT_EMAIL` | Variable | Let's Encrypt 通知メールアドレス |
| `GITHUB_OWNER` | Variable | GHCR オーナー名（例: `s-hikonyan-sys`） |
| `INIT_SSH_PRIVATE_KEY` | Secret | 初回接続用秘密鍵（`alma` 接続で使用） |
| `PROD_SSH_PUBLIC_KEY` | Secret | デプロイ用公開鍵（`artgallery` の `authorized_keys` に登録） |
| `GH_TOKEN_FOR_GHCR` | Secret | GHCR 認証用トークン（`ghcr_token` として注入） |

次に、`art-gallery-release-tools` リポジトリの Settings → Secrets and variables を更新:

| 名前 | 種別 | 更新内容 |
|:---|:---|:---|
| `PROD_SSH_KNOWN_HOSTS` | Secret | 2-1 で取得したホスト鍵で上書き |

必要に応じて以下も確認:

| 名前 | 種別 | 内容 |
|:---|:---|:---|
| `PROD_HOST` | Variable | VPS の IP（変わっていれば更新） |
| `PROD_SSH_USER` | Variable | **`ssh-admin`**（本プレイブック完了後の SSH ユーザー。未設定なら設定） |
| `PROD_SSH_PRIVATE_KEY` | Secret | デプロイ用秘密鍵（変わらなければ不要） |

`PROD_DOMAIN_NAME` は `art-gallery-release-tools` ではなく、`art-gallery-maintenance-tools` の `server_init` ワークフロー（`.github/workflows/server_init.yml`）で参照する。

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

## Phase 4: 検証テスト（任意）

`pytest + testinfra` で、`server-init` 後の状態（sshd/docker/firewalld/AllowUsers/certbot timer 等）を疎結合に検証できる。  
詳細は `docs/SERVER_VERIFY.md` を参照。

最短実行例:

```bash
export TARGET_HOST="YOUR_VPS_GLOBAL_IP"
export TARGET_USER="ssh-admin"
export TARGET_KEY="$HOME/.ssh/sakura_init_key"
export TARGET_DOMAIN="your-domain.com"  # 任意
make server-verify
```

引数で直接指定する場合:

```bash
cd art-gallery-maintenance-tools
pytest -q tests/testinfra \
  --target-host "YOUR_VPS_GLOBAL_IP" \
  --target-user "ssh-admin" \
  --target-key "$HOME/.ssh/sakura_init_key" \
  --target-domain "your-domain.com"
```

定期運用（GHCR PAT 更新、SSH 鍵ローテーション、`known_hosts` 更新、Fail2ban/ジオブロック見直し、Certbot 更新確認）は `docs/SECURITY_ROTATION_RUNBOOK.md` を参照。

---

## トラブルシュート

### Phase 0 で `alma` ユーザーに SSH 接続できない

```bash
# Sakura VPS のシリアルコンソールから接続して確認
ip addr show
# SSH サービス確認
systemctl status sshd
```

### Playbook 完了後に `alma` で SSH できない

想定どおりである。`AllowUsers ssh-admin` 適用後は **`ssh-admin` で接続**する。

```bash
ssh -i ~/.ssh/sakura_init_key ssh-admin@YOUR_VPS_GLOBAL_IP
```

### Ansible 実行中に `UNREACHABLE` エラー

```bash
# Phase 1 実行中は alma で接続テスト
ssh -i ~/.ssh/sakura_init_key alma@YOUR_VPS_GLOBAL_IP
# Playbook 成功後は ssh-admin で
ssh -i ~/.ssh/sakura_init_key ssh-admin@YOUR_VPS_GLOBAL_IP
# known_hosts をクリア（OS 再インストール後は必須）
ssh-keygen -R YOUR_VPS_GLOBAL_IP
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
certbot certonly --standalone --dry-run -d example.com
```

> 注: `-d example.com` はサンプル。実行時は実際に証明書を発行したいドメインを指定する。

詳細な切り分け手順: `docs/SSL_OPERATION.md`

### ジオブロック（firewalld ipset）で Playbook が失敗する

- `firewall-cmd --permanent --add-entries-from-file` が古い firewalld では未サポートの場合がある。その場合は `firewall_geo_block_enabled: false` で無効化し、手動でルールを設計する。
- ipdeny.com への HTTPS 取得がタイムアウトする場合は、しばらく待ってから `--tags init-firewall` のみ再実行。

### Fail2ban が起動しない / sshd ジェイルが無効

```bash
sudo journalctl -u fail2ban -n 50 --no-pager
sudo fail2ban-client -d
```

AlmaLinux 10 で `backend=systemd` が合わない場合は、`ansible/roles/server_init/templates/99-art-gallery.local.j2` の `[sshd]` セクションを `backend = auto` に変更して再デプロイする。
