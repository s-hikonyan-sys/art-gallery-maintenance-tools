# SSL 運用ガイド（server-init 補足）

`docs/SERVER_INIT.md` の `init-ssl` 補足資料。  
現在の Ansible 実装（`ansible/roles/server_init/tasks/ssl.yml`）に合わせ、`certbot certonly --standalone` 前提で記載する。

## 1. 何が自動で行われるか

`make server-init`（または `--tags init-ssl`）で以下を自動実行する。

- `snapd` の導入と有効化
- `certbot`（snap 版）導入
- `certbot certonly --standalone -d <domain>` 実行
- `snap.certbot.renew.timer` の有効化

## 2. 実行前チェック（手動）

```bash
# DNS
dig +short example.com
nslookup example.com
```

> 注: `example.com` は説明用の仮ドメイン。実行時は実ドメインに置き換えること。

- A レコードが対象 VPS のグローバル IPv4 を向いていること
- 80/443 が通信可能であること
- `server_init_vars.yml` の `domain_name` が実ドメインであること（`example.com` のまま実行しない）
- `server_init_vars.yml` の `certbot_email` が設定済みであること

## 3. 実行後チェック（手動）

```bash
# ローカル
curl -I https://example.com

# サーバー（ssh-admin で接続後）
sudo certbot certificates
sudo certbot renew --dry-run
sudo systemctl status snap.certbot.renew.timer
```

> 注: `https://example.com` はサンプルURL。実行時は対象ドメインへ置き換えること。

## 4. よくある失敗

### DNS が未反映

- `dig` / `nslookup` で旧IPが返る間は証明書取得に失敗しやすい
- 反映待ち後に `--tags init-ssl` を再実行する

### 80番ポート疎通不可

- firewalld 設定を確認
- 外形から `http://<domain>` が到達するか確認

### レート制限

- Let's Encrypt の発行回数制限に達していると失敗する
- `certbot renew --dry-run` や staging 環境で検証してから再実行する

## 5. 手動で証明書取得したい場合

Ansible を使わず手動で行う場合（通常は非推奨）:

```bash
sudo certbot certonly --standalone \
  --non-interactive --agree-tos \
  --email you@example.com \
  -d example.com
```

> 注: `-d example.com` はサンプル。実際の発行対象ドメインを指定する。

> 現在の運用では `--nginx` ではなく `certonly --standalone` を採用している。  
> Nginx 側の HTTPS 設定はデプロイ設定側で管理する。

