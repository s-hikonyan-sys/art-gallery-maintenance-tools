# サーバー検証テスト（pytest + testinfra）

`server-init` 実行後に、設定状態を疎結合で検証するための手順。  
Ansible の `inventory` / `group_vars` / `server_init_vars.yml` は読まず、**環境変数または CLI 引数**のみで接続先を指定する。

## 1. 事前準備

ローカル（WSL2）でテスト依存をインストール:

```bash
python3 -m pip install --user pytest testinfra
```

## 2. 検証対象

`tests/testinfra/test_server_init.py` は以下をチェックする。

- `sshd` サービス有効・起動
- `docker` サービス有効・起動
- `ssh-admin` ユーザー存在
- `/etc/ssh/sshd_config` に `AllowUsers ssh-admin`
- firewalld `public` zone で `ssh/http/https` が許可
- `snap.certbot.renew.timer` の有効化
- （任意）証明書一覧に対象ドメインが含まれること

## 3. 実行方法

### 方法A: 環境変数で指定（推奨）

```bash
export TARGET_HOST="YOUR_VPS_GLOBAL_IP"
export TARGET_USER="ssh-admin"
export TARGET_KEY="$HOME/.ssh/sakura_init_key"
export TARGET_DOMAIN="your-domain.com"   # 任意（未設定でも可）
export TARGET_SSH_PORT="22"               # 任意

cd art-gallery-maintenance-tools
pytest -q tests/testinfra
```

### 方法B: CLI 引数で指定

```bash
cd art-gallery-maintenance-tools
pytest -q tests/testinfra \
  --target-host "YOUR_VPS_GLOBAL_IP" \
  --target-user "ssh-admin" \
  --target-key "$HOME/.ssh/sakura_init_key" \
  --target-domain "your-domain.com"
```

## 4. Makefile ショートカット

同リポジトリでは以下でも実行できる（環境変数は同じ）。

```bash
make server-verify
```

## 5. 設計方針（疎結合）

- テストは Ansible の変数ファイルを参照しない
- 期待値（ホスト・ユーザー・鍵・ドメイン）はテスト実行時に注入
- インフラ実装（Ansible）変更とテスト設定を分離できる
