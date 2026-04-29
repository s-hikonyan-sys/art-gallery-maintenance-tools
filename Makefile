COMPOSE = docker compose -f /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/docker-compose.local.yml
ANSIBLE_DIR = /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/ansible
BOOTSTRAP_CONN_VARS = vars/connection_bootstrap.yml
OPERATIONS_CONN_VARS = vars/connection_operations.yml

.PHONY: help setup ghcr-login gen-secrets \
        start-infra start-dev-frontend start-full stop reset-db \
        logs ps \
        server-init server-init-no-ssl install-ansible-collections update-known-hosts \
        server-verify rotate-ghcr-token rotate-ssh-admin-key \
        refresh-ssh-lockdown tune-fail2ban refresh-geo-block verify-certbot-renew

help:
	@echo "============================================================"
	@echo " art-gallery ローカル開発環境 + サーバー管理 コマンド一覧"
	@echo "============================================================"
	@echo ""
	@echo "--- ローカル開発セットアップ ---"
	@echo "  make setup           初回セットアップ（.env・設定ファイル生成）"
	@echo "  make gen-secrets     開発用シークレットファイルを生成"
	@echo "  make ghcr-login      GHCR にログイン（イメージ pull 用）"
	@echo ""
	@echo "--- ローカル開発起動 ---"
	@echo "  make start-infra         secrets-api + postgres のみ起動（バックエンドデバッグ用）"
	@echo "  make start-dev-frontend  上記 + backend コンテナ起動（フロントエンドデバッグ用）"
	@echo "  make start-full          全コンテナ起動（フルスタック確認用）"
	@echo ""
	@echo "--- ローカル開発管理 ---"
	@echo "  make stop            全コンテナ停止"
	@echo "  make reset-db        postgres volume 削除 → 再起動"
	@echo "  make logs            全コンテナのログを follow"
	@echo "  make ps              コンテナ状態確認"
	@echo ""
	@echo "--- サーバー初期構築（OS 再インストール後に使用）---"
	@echo "  make install-ansible-collections  Ansible collections インストール"
	@echo "  make server-init                  本番サーバー初期構築（SSL / Fail2ban / ジオブロック含む）"
	@echo "  make server-init-no-ssl           本番サーバー初期構築（SSL のみスキップ）"
	@echo "  make update-known-hosts           SSH ホスト鍵を取得してコピー"
	@echo "  make server-verify                pytest + testinfra でサーバー状態を検証"
	@echo ""
	@echo "--- 定期運用（ローテーション / 見直し）---"
	@echo "  make rotate-ghcr-token            GHCR トークン反映（init-ghcr のみ）"
	@echo "  make rotate-ssh-admin-key         ssh-admin 公開鍵反映（init-admin-ssh）"
	@echo "  make refresh-ssh-lockdown         SSH 制限再適用（init-ssh-lockdown）"
	@echo "  make tune-fail2ban                Fail2ban 設定反映（init-fail2ban）"
	@echo "  make refresh-geo-block            ジオブロック再構築（init-firewall）"
	@echo "  make verify-certbot-renew         certbot 更新ドライラン（サーバー上で実行）"
	@echo "  ※ 接続ユーザーは vars/connection_*.yml で初回/運用を分離"
	@echo ""
	@echo "詳細は docs/local_dev_guide.md / docs/SERVER_INIT.md を参照してください。"

setup:
	@bash /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/scripts/setup.sh

gen-secrets:
	@python3 /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/scripts/gen-dev-secrets.py

ghcr-login:
	@bash /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/scripts/login-ghcr.sh

# シナリオ B: バックエンドをホストプロセスでデバッグ
start-infra:
	$(COMPOSE) up -d

# シナリオ C: フロントエンドを npm run dev でデバッグ
start-dev-frontend:
	$(COMPOSE) --profile backend up -d

# シナリオ A: フルスタック確認
start-full:
	$(COMPOSE) --profile backend --profile nginx up -d

stop:
	$(COMPOSE) --profile backend --profile nginx down

reset-db:
	$(COMPOSE) --profile backend --profile nginx down -v
	@echo "postgres volume を削除しました。"
	$(COMPOSE) up -d
	@echo "インフラを再起動しました。"

logs:
	$(COMPOSE) --profile backend --profile nginx logs -f

ps:
	$(COMPOSE) --profile backend --profile nginx ps

# ============================================================
# サーバー初期構築
# ============================================================

install-ansible-collections:
	ansible-galaxy collection install -r $(ANSIBLE_DIR)/requirements.yml

server-init: install-ansible-collections
	@if [ ! -f $(ANSIBLE_DIR)/server_init_vars.yml ]; then \
	  echo "❌ $(ANSIBLE_DIR)/server_init_vars.yml が見つかりません。"; \
	  echo "   server_init_vars.yml.example をコピーして設定してください:"; \
	  echo "   cp $(ANSIBLE_DIR)/server_init_vars.yml.example $(ANSIBLE_DIR)/server_init_vars.yml"; \
	  exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(BOOTSTRAP_CONN_VARS)"

server-init-no-ssl: install-ansible-collections
	@if [ ! -f $(ANSIBLE_DIR)/server_init_vars.yml ]; then \
	  echo "❌ $(ANSIBLE_DIR)/server_init_vars.yml が見つかりません。"; \
	  echo "   server_init_vars.yml.example をコピーして設定してください。"; \
	  exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(BOOTSTRAP_CONN_VARS)" \
	  --skip-tags "init-ssl"

update-known-hosts:
	@echo "VPS の SSH ホスト鍵を取得します..."
	@read -p "VPS の IP アドレス: " vps_ip; \
	  ssh-keyscan -t ecdsa $$vps_ip && \
	  echo "" && \
	  echo "👆 上記の行を GitHub Secrets の PROD_SSH_KNOWN_HOSTS に登録してください。"

server-verify:
	pytest -q /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/tests/testinfra

rotate-ghcr-token:
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(OPERATIONS_CONN_VARS)" \
	  --tags "init-ghcr"

rotate-ssh-admin-key:
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(OPERATIONS_CONN_VARS)" \
	  --tags "init-admin-ssh"

refresh-ssh-lockdown:
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(OPERATIONS_CONN_VARS)" \
	  --tags "init-ssh-lockdown"

tune-fail2ban:
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(OPERATIONS_CONN_VARS)" \
	  --tags "init-fail2ban"

refresh-geo-block:
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --extra-vars "@$(OPERATIONS_CONN_VARS)" \
	  --tags "init-firewall"

verify-certbot-renew:
	@if [ -z "$$TARGET_HOST" ]; then \
	  echo "❌ TARGET_HOST が未設定です。例: make verify-certbot-renew TARGET_HOST=YOUR_VPS_GLOBAL_IP"; \
	  exit 1; \
	fi
	@if [ -z "$$TARGET_KEY" ]; then \
	  echo "❌ TARGET_KEY が未設定です。例: make verify-certbot-renew TARGET_HOST=... TARGET_KEY=$$HOME/.ssh/sakura_init_key"; \
	  exit 1; \
	fi
	@TARGET_USER_VAL=$${TARGET_USER:-ssh-admin}; \
	  ssh -i "$$TARGET_KEY" "$$TARGET_USER_VAL@$$TARGET_HOST" "sudo certbot renew --dry-run"
