# SECURITY_ROTATION_RUNBOOK

定期的なセキュリティ運用を、手順として迷わず再実行できるようにまとめたランブックです。
必要に応じて「1項目だけ」実施できるよう、各項目に対応する `make` ターゲットも用意しています。

## 0. 前提

- 作業ディレクトリは `art-gallery-maintenance-tools` のルート。
- ローカル実行時は `ansible/server_init_vars.yml` が最新であること。
- SSH 鍵を使う作業では、必要に応じて `ssh-agent` を利用。
- 接続ユーザーは用途で分離される（初回: `ansible/vars/connection_bootstrap.yml`、運用: `ansible/vars/connection_operations.yml`）。

## 1. GHCR PAT ローテーション（最重要）

### 1-1. GitHub で新しい PAT を作成（fine-grained 画面）

この手順は GitHub の `New fine-grained personal access token` 画面に合わせている。

1. GitHub 右上アイコン → `Settings`。
2. 左メニュー `Developer settings` → `Personal access tokens` → `Fine-grained tokens`。
3. `Generate new token` を開き、`Token name` と `Expiration` を設定。
4. `Repository access` で `Only select repositories` を選び、対象リポジトリを追加（次節参照）。
5. `Permissions` セクションで `Add permissions` を押す。
6. `Repositories` タブで `Packages` を検索して追加し、権限を `Read and write` に設定。
7. `Permissions` に `Packages` が表示されたことを確認して `Generate token`。
8. 表示されたトークン文字列を安全な場所へ一時保存（再表示不可）。

#### PAT 設定（GHCR / push + pull 前提）

| 用途 | 推奨方式 | 必須権限 |
|:---|:---|:---|
| CI/CD および運用で push + pull | fine-grained PAT | `Packages: Read and write` |

- 本リポジトリ運用では `push + pull` を前提としてトークンを作成する。
- `Permissions` が `No repository permissions added yet` のままだと失敗する。
- `delete:packages` は、パッケージ削除運用をしない限り付与しない。

#### fine-grained の `Repository access` で選ぶ対象

`Only select repositories` を使う場合は、次を選択する（不足時は追加）。

- `art-gallery-release-tools`（ビルド workflow 実行元、manifest 更新 PR 作成先）
- `art-gallery-backend`（ソース参照 + GHCR イメージ発行対象）
- `art-gallery-database`（ソース参照 + GHCR イメージ発行対象）
- `art-gallery-secrets`（ソース参照 + GHCR イメージ発行対象）
- `art-gallery-nginx`（ソース参照 + GHCR イメージ発行対象）
- `art-gallery-nginx-base`（`art-gallery-nginx` ビルド時のベースイメージ参照元）

補足:

- `art-gallery-maintenance-tools` は、PAT の配布・反映用途（`server_init`）が主で、GHCR イメージ発行元そのものではない。
- ただし `maintenance-tools` の GitHub Actions で GHCR 操作を行う設計に将来変更する場合は、対象として追加する。

#### なぜ上記リポジトリが必要か（GitHub と GHCR の違い）

- `art-gallery-backend` / `database` / `secrets` / `nginx` は、`release-tools` の workflow から GitHub リポジトリを参照（`git ls-remote` / clone）する。
- その後、ビルド成果物を GHCR へ `docker push` する。
- 本番サーバー側は GHCR から `docker pull` する。
- つまり PAT 設計では、**GitHub リポジトリアクセス要件**と**GHCR アクセス要件**を分けて考える。

#### classic PAT を使う場合（代替）

- `Tokens (classic)` を選択し、`write:packages` + `read:packages` を付与する。
- classic には `Repository access` の選択項目はない（scope 指定のみ）。
- fine-grained で問題が出る場合のフォールバックとして利用する。

### 1-2. 変数を更新

- ローカル運用: `ansible/server_init_vars.yml` の `ghcr_token` を更新。
- GitHub Actions 運用: Repository `Settings` → `Secrets and variables` で該当 secret を更新。

#### PAT 交換時に更新すべき GitHub Actions 設定（必須）

`Settings` → `Secrets and variables` → `Actions` で、以下を更新する。

**`art-gallery-maintenance-tools`**

- `GH_TOKEN_FOR_GHCR`（`server_init.yml` で `ghcr_token` として注入）

**`art-gallery-release-tools`**

- `GH_TOKEN_FOR_ART_GALLERY_RELEASE_TOOLS`（manifest 更新 PR 作成用。`create-pull-request` で使用）
- `GH_TOKEN_FOR_ART_GALLERY_BACKEND`（backend リポジトリ参照用）
- `GH_TOKEN_FOR_ART_GALLERY_DATABASE`（database リポジトリ参照用）
- `GH_TOKEN_FOR_ART_GALLERY_SECRETS`（secrets リポジトリ参照用）
- `GH_TOKEN_FOR_ART_GALLERY_FRONTEND`（frontend リポジトリ参照用。`build_frontend.yml`）
- `GH_TOKEN_FOR_ART_GALLERY_NGINX`（nginx リポジトリ参照用。`deploy_nginx.yml`）

#### Secret 対応表（secret名 / 対象repo / 用途 / 必要権限）

| Secret 名 | 主対象リポジトリ | 主な用途 | 最低限必要な権限（fine-grained） |
|:---|:---|:---|:---|
| `GH_TOKEN_FOR_GHCR` | `art-gallery-maintenance-tools`（+ GHCR） | `server_init.yml` で `ghcr_token` 注入 | `Packages: Read and write`（GHCR 用） |
| `GH_TOKEN_FOR_ART_GALLERY_RELEASE_TOOLS` | `art-gallery-release-tools` | build/register/deploy で manifest 更新 PR 作成 | `Contents: Read and write`, `Pull requests: Read and write` |
| `GH_TOKEN_FOR_ART_GALLERY_BACKEND` | `art-gallery-backend` | `build_backend.yml` / `deploy_backend.yml` で `git ls-remote`・取得 | `Contents: Read-only`（書き込みしない運用時） |
| `GH_TOKEN_FOR_ART_GALLERY_DATABASE` | `art-gallery-database` | `build_database.yml` / `deploy_database.yml` で参照 | `Contents: Read-only` |
| `GH_TOKEN_FOR_ART_GALLERY_SECRETS` | `art-gallery-secrets` | `build_secrets.yml` / `deploy_secrets.yml` で参照 | `Contents: Read-only` |
| `GH_TOKEN_FOR_ART_GALLERY_FRONTEND` | `art-gallery-frontend` | `build_frontend.yml` で参照 | `Contents: Read-only` |
| `GH_TOKEN_FOR_ART_GALLERY_NGINX` | `art-gallery-nginx` | `deploy_nginx.yml` で参照 | `Contents: Read-only` |

補足:

- 上記は「GitHub リポジトリ参照用トークン」。GHCR 操作権限（`Packages:*`）とは分けて管理する。
- `release-tools` 自体の manifest PR 作成失敗（`could not read Username ...`）は、`GH_TOKEN_FOR_ART_GALLERY_RELEASE_TOOLS` の失効/権限不足が典型原因。

#### 権限の注意（fine-grained）

- `GH_TOKEN_FOR_ART_GALLERY_RELEASE_TOOLS` は少なくとも `art-gallery-release-tools` に対して `Contents: Read and write` と `Pull requests: Read and write` が必要。
- 各サービス用トークン（backend/database/secrets/frontend/nginx）は、対象リポジトリへの参照に必要な権限を付与する。
- GHCR push/pull を行うトークンは `Packages: Read and write` を付与する。

### 1-3. サーバーへ反映

```bash
make rotate-ghcr-token
```

上記は運用用接続ユーザー（`ssh-admin`）で実行される。初回構築時の `alma` 接続とは Makefile 側で分離済み。

### 1-3a. 最短実行手順（迷ったらこれだけ）

```bash
cd art-gallery-maintenance-tools
nano ansible/server_init_vars.yml
make rotate-ghcr-token
```

### 1-4. 動作確認

- サーバー上の `docker login ghcr.io` が成功すること。
- デプロイ時に GHCR pull が成功すること。

## 2. SSH 鍵ローテーション

### 2-1. 管理用鍵（ssh-admin）更新

1. 新しい鍵ペアを作成（例: `~/.ssh/sakura_init_key_YYYYMM`）。
2. `ansible/server_init_vars.yml` の `admin_ssh_public_key` を新しい公開鍵へ更新。
3. 反映:

```bash
make rotate-ssh-admin-key
```

4. 新鍵で `ssh-admin@YOUR_VPS_GLOBAL_IP` へログイン確認後、旧鍵を段階的に廃止。

## 3. known_hosts 更新

サーバー再構築やホスト鍵変更時に実施します。

```bash
make update-known-hosts
```

必要なら対象ホストを変更:

```bash
make update-known-hosts HOST=YOUR_VPS_GLOBAL_IP
```

## 4. SSH 制限（AllowUsers / PasswordAuthentication）再適用

`sshd_config` の意図しない変更を戻したいときに実施します。

```bash
make refresh-ssh-lockdown
```

反映後は `ssh-admin` で再ログイン確認を行ってください。

## 5. Fail2ban チューニング反映

`ansible/server_init_vars.yml` の Fail2ban 関連値を調整した後に実施します。

```bash
make tune-fail2ban
```

確認例（サーバー上）:

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

## 6. ジオブロック設定の再構築

許可/拒否対象の国コードや CIDR リスト見直し後に実施します。

```bash
make refresh-geo-block
```

確認例（サーバー上）:

```bash
sudo firewall-cmd --list-all --zone=public
sudo ipset list
```

## 7. Certbot 自動更新の健全性確認

更新処理のドライランだけ個別に実行できます。

```bash
make verify-certbot-renew TARGET_HOST=YOUR_VPS_GLOBAL_IP TARGET_KEY=$HOME/.ssh/sakura_init_key
```

必要に応じて接続ユーザーを指定:

```bash
make verify-certbot-renew TARGET_HOST=YOUR_VPS_GLOBAL_IP TARGET_KEY=$HOME/.ssh/sakura_init_key TARGET_USER=ssh-admin
```

追加確認（サーバー上）:

```bash
sudo systemctl status snap.certbot.renew.timer
sudo certbot renew --dry-run
```

## 8. 推奨頻度

- GHCR PAT: 有効期限に合わせて、期限切れ前に必ず更新。
- SSH 鍵: 半年〜1年を目安にローテーション。
- Fail2ban/ジオブロック: 月次または攻撃傾向変化時に見直し。
- Certbot 更新確認: 月次、または大きなネットワーク変更後。

