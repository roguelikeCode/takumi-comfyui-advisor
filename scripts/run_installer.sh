#!/bin/bash

# ==============================================================================
# Takumi Installer Session Manager
#
# [Why] To orchestrate the installation process from the Host OS.
# [What] Manages Docker lifecycle, injects secrets via dotenvx, and handles the retry loop.
# ==============================================================================

# --- Strict Mode ---
set -euo pipefail

# ==============================================================================
# [1] Configuration (Encapsulation)
# ==============================================================================

# Container Settings
readonly IMAGE_NAME="takumi-comfyui"
readonly IMAGE_TAG="latest"
readonly CONTAINER_NAME="takumi-comfyui-oss"

# File Paths
readonly CURRENT_DIR="$(pwd)"
readonly HISTORY_FILE="cache/.install_history"

# [Why] To define volume mappings in a readable, maintainable format.
# [What] Returns an array of Docker volume arguments.
get_volume_args() {
    echo \
        "-v ${CURRENT_DIR}/cache:/app/cache" \
        "-v ${CURRENT_DIR}/logs:/app/logs" \
        "-v ${CURRENT_DIR}/external:/app/external" \
        "-v ${CURRENT_DIR}/app:/app" \
        "-v ${CURRENT_DIR}/scripts:/app/scripts:ro" \
        "-v ${CURRENT_DIR}/storage/pkgs:/home/.conda/pkgs" \
        "-v ${CURRENT_DIR}/storage/envs:/home/.conda/envs" \
        "-v ${CURRENT_DIR}/storage/ollama:/home/.ollama" \
        "-v ${CURRENT_DIR}/${HISTORY_FILE}:/app/${HISTORY_FILE}"
}

# ==============================================================================
# [2] Helper Functions (Abstraction)
# ==============================================================================

# [Why] To ensure the history file exists and is a valid file (not a dir).
# [What] Removes directory if conflict exists, touches file.
ensure_history_file() {
    if [ -d "$HISTORY_FILE" ]; then
        echo "Removing directory '$HISTORY_FILE' to replace with a file..."
        rm -rf "$HISTORY_FILE"
    fi
    touch "$HISTORY_FILE"
}

# [Why] To construct the correct execution command based on environment capabilities.
# [What] Wraps docker command with dotenvx if available to decrypt secrets.
execute_docker_run() {
    local docker_cmd=(
        docker run -it
        --rm
        --gpus all
        --env-file .env
        -e HF_TOKEN # Inject decrypted token
        -e PYTHONDONTWRITEBYTECODE=1
        -e CONDA_ENVS_DIRS=/root/.conda/envs \
	    -e CONDA_PKGS_DIRS=/root/.conda/pkgs \
        --name "$CONTAINER_NAME"
        -w /app
        -e HOME=/home
        --security-opt no-new-privileges:true
        --cap-drop=ALL
        --cap-add=SYS_NICE
    )

    # Append volumes dynamically
    docker_cmd+=($(get_volume_args))

    # Append Image and Command
    docker_cmd+=("${IMAGE_NAME}:${IMAGE_TAG}" bash /app/install.sh)

    # [Logic] Wrap with dotenvx if installed
    if command -v dotenvx >/dev/null 2>&1; then
        dotenvx run -- "${docker_cmd[@]}"
    else
        "${docker_cmd[@]}"
    fi
}

# ==============================================================================
# [3] Main Session Loop
# ==============================================================================

main() {
    ensure_history_file

    while true; do
        echo "--- Starting new installation attempt ---"

        # Execute the containerized installer
        # The exit code determines if we succeeded or failed
        if execute_docker_run; then
            echo "✅ Installation successful!"
            rm -f "$HISTORY_FILE"
            break
        else
            local exit_code=$?
            
            # Special case: User explicitly aborted or reported via GUI logic (125)
            if [ "$exit_code" -eq 125 ]; then
                echo "🛑 Report submitted to The Takumi as requested. Process finished."
                rm -f "$HISTORY_FILE"
                break
            fi

            # Standard failure: Ask for retry
            read -p "Installation failed. Retry with a different strategy? (Y/n): " consent
            if [[ "${consent,,}" == "n" ]]; then
                echo "Aborted by user."
                rm -f "$HISTORY_FILE"
                break
            fi
            echo "Acknowledged. Preparing for another attempt..."
        fi
    done
}

# --- Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi