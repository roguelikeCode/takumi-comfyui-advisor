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
readonly DOCKER_RUN_OPTS="--rm \
	--name $CONTAINER_NAME \
	-v $(pwd)/cache:/app/cache \
	-v $(pwd)/logs:/app/logs \
	-v $(pwd)/external:/app/external"


# --- Main Loop ---
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