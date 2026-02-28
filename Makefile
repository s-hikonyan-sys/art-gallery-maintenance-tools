COMPOSE = docker compose -f /home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/docker-compose.local.yml

.PHONY: help setup ghcr-login gen-secrets \
        start-infra start-dev-frontend start-full stop reset-db \
        logs ps

help:
	@echo "============================================================"
	@echo " art-gallery ローカル開発環境 コマンド一覧"
	@echo "============================================================"
	@echo ""
	@echo "--- セットアップ ---"
	@echo "  make setup           初回セットアップ（.env・設定ファイル生成）"
	@echo "  make gen-secrets     開発用シークレットファイルを生成"
	@echo "  make ghcr-login      GHCR にログイン（イメージ pull 用）"
	@echo ""
	@echo "--- 起動 ---"
	@echo "  make start-infra         secrets-api + postgres のみ起動（バックエンドデバッグ用）"
	@echo "  make start-dev-frontend  上記 + backend コンテナ起動（フロントエンドデバッグ用）"
	@echo "  make start-full          全コンテナ起動（フルスタック確認用）"
	@echo ""
	@echo "--- 管理 ---"
	@echo "  make stop            全コンテナ停止"
	@echo "  make reset-db        postgres volume 削除 → 再起動"
	@echo "  make logs            全コンテナのログを follow"
	@echo "  make ps              コンテナ状態確認"
	@echo ""
	@echo "詳細は docs/local_dev_guide.md を参照してください。"

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
