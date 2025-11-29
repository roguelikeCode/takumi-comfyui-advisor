# ==============================================================================
# Takumi Installer Wrapper Script
#
# Description: This script orchestrates the installation process, handling the
#              retry loop and user interaction outside of the Makefile.
# ==============================================================================

#!/bin/bash

# --- Strict Mode & Safety ---
set -euo pipefail

# --- Configuration (matches Makefile) ---
readonly IMAGE_NAME="takumi-comfyui"
readonly IMAGE_TAG="latest"
readonly CONTAINER_NAME="takumi-comfyui-dev"
readonly HISTORY_FILE=".install_history"

# --- Docker Run Options ---
# [修正] MakefileのDOCKER_RUN_OPTSと同じ設定にする必要があります
# 特に、storage/envs のマウントが重要です
# [追加] パッケージキャッシュをマウント (権限エラー回避 & 高速化)
readonly DOCKER_RUN_OPTS="--rm \
    --gpus all \
    --name $CONTAINER_NAME \
    --user $(id -u):$(id -g) \
    -w /app \
    -e HOME=/home/takumi \
    -v $(pwd)/cache:/app/cache \
    -v $(pwd)/logs:/app/logs \
    -v $(pwd)/external:/app/external \
    -v $(pwd)/app:/app \
    -v $(pwd)/scripts:/app/scripts \
    -v $(pwd)/storage/pkgs:/home/takumi/.conda/pkgs \
    -v $(pwd)/storage/envs:/home/takumi/.conda/envs \
    -v $(pwd)/storage/ollama:/home/takumi/.ollama" 

# --- Main Loop ---

# [修正] 安全装置: もしディレクトリとして存在してしまっていたら削除する
if [ -d "$HISTORY_FILE" ]; then
    echo "Removing directory '$HISTORY_FILE' to replace with a file..."
    rm -rf "$HISTORY_FILE"
fi

# 空の履歴ファイルを作成（なければ作成、あればタイムスタンプ更新）
touch "$HISTORY_FILE"

while true; do
    echo "--- Starting new installation attempt ---"

    docker run -it $DOCKER_RUN_OPTS \
        -v "$(pwd)/$HISTORY_FILE":/app/.install_history \
        "$IMAGE_NAME:$IMAGE_TAG" \
        bash /app/install.sh

    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ Installation successful!"
        rm -f "$HISTORY_FILE"
        break
    else
        read -p "Installation failed. Retry with a different strategy? (Y/n): " consent
        if [[ "${consent,,}" == "n" ]]; then
            if [ $exit_code -eq 125 ]; then
                echo "🛑 Report submitted to The Takumi as requested. Process finished."
            else
                echo "Aborted by user."
            fi
            rm -f "$HISTORY_FILE"
            break
        fi
        echo "Acknowledged. Preparing for another attempt..."
    fi
done