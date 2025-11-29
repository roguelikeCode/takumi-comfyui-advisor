#!/bin/bash
set -e

ENV_NAME="magic_clothing_env"

# Condaの設定読み込み
source /opt/conda/etc/profile.d/conda.sh

# [追加] 環境が存在するかチェック
if ! conda env list | grep -q "${ENV_NAME}"; then
    echo "🔴 Error: Conda environment '${ENV_NAME}' not found."
    echo "👉 Please run 'make install' first to set up the environment."
    exit 1
fi

echo ">>> Activating Conda environment: ${ENV_NAME}..."
conda activate "${ENV_NAME}"

# ComfyUIディレクトリのチェック
if [ ! -d "/app/ComfyUI" ]; then
    echo "🔴 Error: ComfyUI directory not found."
    echo "👉 Please run 'make install' first."
    exit 1
fi

echo ">>> Setting up Takumi Bridge..."
# [Why] 開発中の拡張機能をComfyUIに認識させるため
# [What] app/takumi_bridge へのシンボリックリンクを作成する
TARGET_LINK="/app/ComfyUI/custom_nodes/ComfyUI-Takumi-Bridge"
SOURCE_DIR="/app/takumi_bridge"

if [ -d "$SOURCE_DIR" ]; then
    # リンクがなければ作成
    if [ ! -L "$TARGET_LINK" ]; then
        ln -s "$SOURCE_DIR" "$TARGET_LINK"
        echo "✅ Linked Takumi Bridge to custom_nodes."
    fi
else
    echo "⚠️ Takumi Bridge source not found at $SOURCE_DIR"
fi

cd /app/ComfyUI

echo ">>> Starting ComfyUI..."
# --listen 0.0.0.0 で外部アクセスを許可
python main.py --listen 0.0.0.0 --port 8188