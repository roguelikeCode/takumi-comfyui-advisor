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

cd /app/ComfyUI

echo ">>> Starting ComfyUI..."
# --listen 0.0.0.0 で外部アクセスを許可
python main.py --listen 0.0.0.0 --port 8188