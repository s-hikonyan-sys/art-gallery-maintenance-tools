# SECURITY_ROTATION_RUNBOOK

定期的なセキュリティ運用を、手順として迷わず再実行できるようにまとめたランブックです。
必要に応じて「1項目だけ」実施できるよう、各項目に対応する `make` ターゲットも用意しています。

## 0. 前提

- 作業ディレクトリは `art-gallery-maintenance-tools` のルート。
- ローカル実行時は `ansible/server_init_vars.yml` が最新であること。
- SSH 鍵を使う作業では、必要に応じて `ssh-agent` を利用。

## 1. GHCR PAT ローテーション（最重要）

### 1-1. GitHub で新しい PAT を作成

1. GitHub 右上アイコン → `Settings`。
2. 左メニュー `Developer settings` → `Personal access tokens`。
3. 方式を選択（このリポジトリ運用では `Tokens (classic)` 推奨）。
4. `Generate new token` を選択し、用途が分かる名前・有効期限を設定。
5. 用途に応じてスコープを付与（下表）。
6. 生成直後に表示されるトークン文字列を安全な場所へ一時保存（再表示不可）。

#### PAT 設定（GHCR / push + pull 前提）

| 用途 | 推奨方式 | 必須権限 |
|:---|:---|:---|
| CI/CD および運用で push + pull | classic PAT | `write:packages` + `read:packages` |

- private repository を扱う運用では、状況により `repo` が必要になる場合がある。
- `delete:packages` は、パッケージ削除運用をしない限り付与しない。
- 本リポジトリ運用では `push + pull` を前提としてトークンを作成する。

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

#### fine-grained PAT を使う場合

- `Permissions` が空（`No account permissions added yet`）だと失敗する。
- 少なくとも `Packages` を追加し、用途に応じて `Read` または `Read and write` を設定する。
- `Repository access` は対象リポジトリだけに絞る（`Only select repositories` 推奨）。
- `Only select repositories` では、GHCR の push/pull に使うリポジトリのみ選択する。
- 一時的に `All repositories` を使うことは可能だが、確認後に最小範囲へ絞る。
- `Tokens (classic)` には `Repository access` の選択項目はなく、scope 指定で権限を付与する。

### 1-2. 変数を更新

- ローカル運用: `ansible/server_init_vars.yml` の `ghcr_token` を新トークンに更新。
- GitHub Actions 運用: Repository `Settings` → `Secrets and variables` で該当 secret を更新。

### 1-3. サーバーへ反映

```bash
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

### 2-2. デプロイ用鍵（artgallery）更新

1. デプロイ専用の新しい鍵ペアを作成。
2. `ansible/server_init_vars.yml` の `deploy_ssh_public_key` を更新。
3. 反映:

```bash
make rotate-deploy-key
```

4. デプロイツール側の秘密鍵設定も同時に差し替えて疎通確認。

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

