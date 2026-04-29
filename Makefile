COMPOSE = docker compose -f /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/docker-compose.local.yml
ANSIBLE_DIR = /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/ansible

.PHONY: help setup ghcr-login gen-secrets \
        start-infra start-dev-frontend start-full stop reset-db \
        logs ps \
        server-init server-init-no-ssl install-ansible-collections update-known-hosts \
        server-verify

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
	  --extra-vars "@server_init_vars.yml"

server-init-no-ssl: install-ansible-collections
	@if [ ! -f $(ANSIBLE_DIR)/server_init_vars.yml ]; then \
	  echo "❌ $(ANSIBLE_DIR)/server_init_vars.yml が見つかりません。"; \
	  echo "   server_init_vars.yml.example をコピーして設定してください。"; \
	  exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbook_server_init.yml \
	  --inventory inventory/production_init.yml \
	  --extra-vars "@server_init_vars.yml" \
	  --skip-tags "init-ssl"

update-known-hosts:
	@echo "VPS の SSH ホスト鍵を取得します..."
	@read -p "VPS の IP アドレス: " vps_ip; \
	  ssh-keyscan -t ecdsa $$vps_ip && \
	  echo "" && \
	  echo "👆 上記の行を GitHub Secrets の PROD_SSH_KNOWN_HOSTS に登録してください。"

server-verify:
	pytest -q /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/tests/testinfra
