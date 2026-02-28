# ローカル開発環境 手順書

## 前提条件

- Windows + WSL2 (Ubuntu)
- Docker Desktop（WSL2 backend）インストール済み
- Python 3.11 以上インストール済み（シナリオB でバックエンドをローカル起動する場合）
- Node.js 18 以上インストール済み（シナリオC でフロントエンドをローカル起動する場合）
- 各リポジトリを WSL2 の Linux ファイルシステム上にクローン済み
  - 推奨クローン先: `/home/<user>/art-gallery/<repo-name>/`
  - **NG: `/mnt/c/` 以下への配置**（ファイルパーミッション問題・パフォーマンス低下のため）

## シナリオ一覧

| シナリオ | Docker で起動 | ローカルで起動 |
|---|---|---|
| [A] フルスタック確認 | secrets-api, postgres, backend, nginx | なし |
| [B] バックエンドデバッグ | secrets-api, postgres | backend（Flask / VS Code debugger） |
| [C] フロントエンドデバッグ | secrets-api, postgres, backend | frontend（npm run dev） |

---

## 初回セットアップ（全シナリオ共通）

### 1. art-gallery-maintenance-tools をクローン

```bash
cd /home/<user>/art-gallery
git clone https://github.com/s-hikonyan-sys/art-gallery-maintenance-tools.git
cd art-gallery-maintenance-tools
```

### 2. セットアップスクリプトを実行

```bash
make setup
```

実行されること:
- `local/.env` を `.env.example` からコピー
- `local/conf/` 以下の実設定ファイルを `*.example` からコピー
- `/etc/hosts` に `127.0.0.1 art-gallery-dev-api` を追加

> `/etc/hosts` への書き込みには `sudo` パスワードが求められます。

### 3. `.env` を編集して各リポジトリのパスを設定

```bash
nano /home/<user>/art-gallery/art-gallery-maintenance-tools/local/.env
```

```dotenv
SECRETS_REPO_PATH=/home/<user>/art-gallery/art-gallery-secrets
BACKEND_REPO_PATH=/home/<user>/art-gallery/art-gallery-backend
DATABASE_REPO_PATH=/home/<user>/art-gallery/art-gallery-database
NGINX_REPO_PATH=/home/<user>/art-gallery/art-gallery-nginx
FRONTEND_REPO_PATH=/home/<user>/art-gallery/art-gallery-frontend
GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxx
```

`<user>` を実際の WSL2 ユーザー名に置き換えてください。

### 4. 開発用シークレットを生成

```bash
make gen-secrets
```

実行されること:
- ランダムな `secret_key` を生成し `local/conf/secrets/config/config.yaml` に書き込む
- 開発用 DB パスワード `dev_password_local_12345` を暗号化し
  `local/conf/secrets/config/secrets.yaml.encrypted` に書き込む

### 5. GHCR にログイン

```bash
make ghcr-login
```

`.env` の `GHCR_TOKEN` を使って `ghcr.io` にログインします（`read:packages` 権限が必要）。

---

## シナリオ A: フルスタック確認

全サービスをコンテナで動かし、本番構成に近い状態で動作確認します。

### A-1. フロントエンドをビルド

```bash
cd /home/<user>/art-gallery/art-gallery-frontend
npm install
npm run build
# dist/ ディレクトリが生成されることを確認
```

### A-2. 全コンテナを起動

```bash
cd /home/<user>/art-gallery/art-gallery-maintenance-tools
make start-full
```

### A-3. 起動確認

```bash
make ps
```

以下の 4 コンテナが `Up` になること:
- `art-gallery-secrets-api-dev`
- `art-gallery-db-dev`
- `art-gallery-dev-api`
- `art-gallery-nginx-dev`

### A-4. ブラウザで確認

Docker Desktop 使用時は Windows 側のブラウザから:
```
http://localhost:80
```

### A-5. backend の設定ファイル（コンテナ用）

`local/conf/backend/config.yaml` の状態:

```yaml
database:
  host: art-gallery-db-dev     # Docker ネットワーク内のコンテナ名
  port: 5432
  name: art_gallery_dev
  user: artuser

secrets_api:
  url: http://art-gallery-secrets-api-dev:5000    # Docker ネットワーク内のコンテナ名
  # token_file の指定は不要（コンテナ内デフォルト /app/tokens/ を使用）
```

### A-6. 停止

```bash
make stop
```

---

## シナリオ B: バックエンドデバッグ

backend をホストプロセス（Flask または VS Code debugger）で起動し、
secrets-api と postgres はコンテナで動かします。

### B-1. インフラを起動

```bash
cd /home/<user>/art-gallery/art-gallery-maintenance-tools
make start-infra
```

### B-2. 起動確認

```bash
make ps
# art-gallery-secrets-api-dev, art-gallery-db-dev が healthy になること
```

secrets-api が healthy になるまで最大 50 秒かかります。

### B-3. backend の設定ファイルをホストプロセス用に変更

`local/conf/backend/config.yaml` を編集:

```yaml
database:
  host: localhost               # ← コンテナ名から変更（docker-compose で 5432:5432 公開済み）
  port: 5432
  name: art_gallery_dev
  user: artuser

secrets_api:
  url: http://localhost:5000    # ← コンテナ名から変更（docker-compose で 5000:5000 公開済み）
  token_file: /home/<user>/art-gallery/art-gallery-maintenance-tools/local/conf/secrets/tokens/backend_token.txt
  # ↑ docker-compose.local.yml で ./conf/secrets/tokens:/app/tokens:rw でホストにマウント済み
```

> `<user>` は実際のユーザー名に置き換えてください。

### B-4. backend のコード側に config.yaml を向ける

backend コンテナとホストプロセスは異なる config.yaml を使うため、
シンボリックリンクで maintenance-tools の設定ファイルに向けます。

```bash
# 既存の config.yaml があれば退避
mv /home/<user>/art-gallery/art-gallery-backend/config/config.yaml \
   /home/<user>/art-gallery/art-gallery-backend/config/config.yaml.bak 2>/dev/null || true

# maintenance-tools の設定ファイルにシンボリックリンクを貼る
ln -sf /home/<user>/art-gallery/art-gallery-maintenance-tools/local/conf/backend/config.yaml \
       /home/<user>/art-gallery/art-gallery-backend/config/config.yaml
```

### B-5. backend をローカルで起動

```bash
cd /home/<user>/art-gallery/art-gallery-backend

# 仮想環境のセットアップ（初回のみ）
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Flask で起動
source venv/bin/activate
python app.py
```

**VS Code でデバッグする場合:**

`.vscode/launch.json` に以下を追加:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flask Debug",
      "type": "debugpy",
      "request": "launch",
      "module": "flask",
      "args": ["run", "--host=0.0.0.0", "--port=8080", "--no-debugger"],
      "env": {
        "FLASK_APP": "app.py",
        "FLASK_ENV": "development"
      },
      "cwd": "/home/<user>/art-gallery/art-gallery-backend"
    }
  ]
}
```

### B-6. 動作確認

```bash
# ヘルスチェック
curl http://localhost:8080/api/health
# {"status": "healthy"} が返ること
```

### B-7. 停止・後片付け

```bash
# Flask プロセスを Ctrl+C で停止

# コンテナ停止
cd /home/<user>/art-gallery/art-gallery-maintenance-tools
make stop

# シンボリックリンクを削除（他のシナリオに戻す場合）
rm /home/<user>/art-gallery/art-gallery-backend/config/config.yaml
mv /home/<user>/art-gallery/art-gallery-backend/config/config.yaml.bak \
   /home/<user>/art-gallery/art-gallery-backend/config/config.yaml 2>/dev/null || true
```

---

## シナリオ C: フロントエンドデバッグ

frontend を Vite dev server（`npm run dev`）で起動し、
secrets-api、postgres、backend はコンテナで動かします。

### C-1. インフラ + backend コンテナを起動

```bash
cd /home/<user>/art-gallery/art-gallery-maintenance-tools

make start-dev-frontend
```

### C-2. 起動確認

```bash
make ps
# art-gallery-secrets-api-dev, art-gallery-db-dev, art-gallery-dev-api が healthy / Up になること
```

### C-3. backend の設定ファイル（コンテナ用）

`local/conf/backend/config.yaml` が以下の状態であること（シナリオA と同じ）:

```yaml
database:
  host: art-gallery-db-dev
secrets_api:
  url: http://art-gallery-secrets-api-dev:5000
  # token_file の指定は不要
```

### C-4. フロントエンドをローカルで起動

```bash
cd /home/<user>/art-gallery/art-gallery-frontend

# 依存関係インストール（初回のみ）
npm install

# Vite dev server 起動（ポート 3000）
npm run dev
```

Vite の `vite.config.js` は `/api` へのリクエストを `http://art-gallery-dev-api:8080` に
プロキシします。`make setup` で `/etc/hosts` に `127.0.0.1 art-gallery-dev-api` を
追加済みのため、WSL2 ホスト上の Node.js プロセスからコンテナ名でアクセス可能です。

### C-5. ブラウザで確認

```
http://localhost:3000
```

HMR（Hot Module Replacement）が有効なため、ファイル保存で即座にブラウザに反映されます。

### C-6. 停止

```bash
# npm run dev を Ctrl+C で停止

cd /home/<user>/art-gallery/art-gallery-maintenance-tools
make stop
```

---

## データベースのリセット

マイグレーションをやり直したい場合:

```bash
cd /home/<user>/art-gallery/art-gallery-maintenance-tools

# postgres volume を削除 → 全コンテナ停止 → インフラを再起動
make reset-db
```

---

## トラブルシューティング

### secrets-api が healthy にならない

```bash
# ログを確認
docker logs art-gallery-secrets-api-dev

# 設定ファイルの存在確認
ls -la /home/<user>/art-gallery/art-gallery-maintenance-tools/local/conf/secrets/config/
# config.yaml と secrets.yaml.encrypted が存在すること

# gen-secrets を再実行
make gen-secrets
# その後コンテナを再起動
docker restart art-gallery-secrets-api-dev
```

### backend が「トークンファイルが見つかりません」エラー

```bash
# トークンファイルの存在確認
ls -la /home/<user>/art-gallery/art-gallery-maintenance-tools/local/conf/secrets/tokens/
# backend_token.txt が存在すること（secrets-api が健康になると生成される）

# secrets-api が healthy か確認
make ps

# secrets-api を再起動して tokens を再生成
docker restart art-gallery-secrets-api-dev
# （DEV_MODE=true のため自動終了しない）
```

### vite.config.js のプロキシが失敗する（ECONNREFUSED）

```bash
# /etc/hosts の確認
grep art-gallery-dev-api /etc/hosts
# 127.0.0.1 art-gallery-dev-api が存在すること

# ない場合は手動追加
echo "127.0.0.1 art-gallery-dev-api" | sudo tee -a /etc/hosts

# backend コンテナが起動しているか確認
make ps
# art-gallery-dev-api が Up であること
```

### postgres に接続できない

```bash
# postgres コンテナが healthy か確認
make ps

# ポート接続テスト
nc -z localhost 5432 && echo "OK" || echo "NG"

# ローカルから psql で接続テスト
psql -h localhost -p 5432 -U artuser -d art_gallery_dev
```

### GHCR からイメージを pull できない（denied）

```bash
# GHCR にログインし直す
make ghcr-login

# または手動でログイン
echo "ghp_xxx" | docker login ghcr.io -u s-hikonyan-sys --password-stdin

# その後イメージを pull
docker pull ghcr.io/s-hikonyan-sys/art-gallery-secrets:latest
docker pull ghcr.io/s-hikonyan-sys/art-gallery-backend:latest
docker pull ghcr.io/s-hikonyan-sys/art-gallery-database:latest
```

### Windows ブラウザから localhost にアクセスできない

Docker Desktop（WSL2 backend）使用時は自動でポートフォワードされます。
アクセスできない場合は Docker Desktop を再起動してください。

WSL2 native Docker の場合:
```bash
# WSL2 の IP を確認
wsl hostname -I
# 表示された IP で Windows ブラウザからアクセス: http://<wsl-ip>:80
```
