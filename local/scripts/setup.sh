#!/bin/bash
# 初回セットアップスクリプト
# make setup から呼び出される

set -e

LOCAL_DIR="/home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local"

echo "============================================================"
echo " art-gallery ローカル開発環境 初回セットアップ"
echo "============================================================"
echo ""

# .env ファイルの作成
if [ ! -f "${LOCAL_DIR}/.env" ]; then
    cp "${LOCAL_DIR}/.env.example" "${LOCAL_DIR}/.env"
    echo "[OK] .env ファイルを作成しました"
    echo "     → 編集してください: ${LOCAL_DIR}/.env"
else
    echo "[SKIP] .env ファイルは既に存在します"
fi

# conf/ の実設定ファイルを example から作成
echo ""
echo "--- 設定ファイルの作成 ---"
for example_file in $(find "${LOCAL_DIR}/conf" -name "*.example" | sort); do
    actual_file="${example_file%.example}"
    if [ ! -f "${actual_file}" ]; then
        cp "${example_file}" "${actual_file}"
        echo "[OK] 作成: ${actual_file}"
    else
        echo "[SKIP] 既存: ${actual_file}"
    fi
done

# tokens ディレクトリの確認
mkdir -p "${LOCAL_DIR}/conf/secrets/tokens"
echo "[OK] tokens ディレクトリを確認しました"

# /etc/hosts への art-gallery-dev-api 追加
# vite.config.js のプロキシターゲット "art-gallery-dev-api:8080" を
# WSL2 ホストから解決できるようにする
echo ""
echo "--- /etc/hosts の設定 ---"
if grep -q "art-gallery-dev-api" /etc/hosts 2>/dev/null; then
    echo "[SKIP] art-gallery-dev-api は既に /etc/hosts に存在します"
else
    echo "127.0.0.1 art-gallery-dev-api" | sudo tee -a /etc/hosts > /dev/null
    echo "[OK] 127.0.0.1 art-gallery-dev-api を /etc/hosts に追加しました"
fi

echo ""
echo "============================================================"
echo " セットアップ完了"
echo "============================================================"
echo ""
echo "次のステップ:"
echo "  1. ${LOCAL_DIR}/.env を編集して各リポジトリのパスと GHCR_TOKEN を設定"
echo "  2. make gen-secrets  （開発用シークレットを生成）"
echo "  3. make ghcr-login   （GHCR にログイン）"
echo "  4. make start-infra  （インフラを起動）"
echo ""
echo "詳細は docs/local_dev_guide.md を参照してください。"
