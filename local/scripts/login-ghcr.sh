#!/bin/bash
# GHCR ログインスクリプト
# make ghcr-login から呼び出される

set -e

LOCAL_DIR="/home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local"

if [ ! -f "${LOCAL_DIR}/.env" ]; then
    echo "エラー: .env ファイルが見つかりません"
    echo "先に make setup を実行してください"
    exit 1
fi

# .env を読み込む
set -a
source "${LOCAL_DIR}/.env"
set +a

if [ -z "${GHCR_TOKEN}" ] || [ "${GHCR_TOKEN}" = "ghp_xxxxxxxxxxxxxxxx" ]; then
    echo "エラー: .env の GHCR_TOKEN が設定されていません"
    echo "GitHub > Settings > Developer settings > Personal access tokens で"
    echo "read:packages 権限を持つトークンを作成し、.env に設定してください"
    exit 1
fi

echo "${GHCR_TOKEN}" | docker login ghcr.io -u s-hikonyan-sys --password-stdin
echo "[OK] GHCR にログインしました"
