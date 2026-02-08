#!/bin/bash

# ==============================================================================
# Takumi Runtime Engine v3.0 (Sovereign Edition)
#
# [Role] Container Entrypoint
# [Responsibility]
#   1. Safety Check (Prevent restart loops if empty)
#   2. Environment Activation (Conda)
#   3. Service Orchestration (Bridge, Brain)
#   4. Application Launch (ComfyUI)
# ==============================================================================

# --- 1. Import Utilities ---
# [Why] Load constants from the single source of truth (utils.sh).
# Do NOT redefine readonly variables here.

if [ -f "/app/lib/utils.sh" ]; then source "/app/lib/utils.sh"; fi
if [ -f "/app/lib/logger.sh" ]; then source "/app/lib/logger.sh"; fi

# [Fallback] Logger
if ! command -v log_info &> /dev/null; then
    log_info() { echo "INFO: $1"; }
    log_warn() { echo "WARN: $1"; }
    log_error() { echo "ERROR: $1"; }
    log_success() { echo "SUCCESS: $1"; }
fi

# [Config] Local constants (Not in utils.sh)
readonly COMFY_PORT=8188
readonly OLLAMA_LOG="${APP_ROOT}/logs/ollama.log"
readonly BRAIN_HOST="${OLLAMA_HOST:-http://ollama:11434}"

# [CRITICAL] Temporarily disable exit-on-error for pre-flight checks
set +e

# ==============================================================================
# 2. Safety Mechanisms
# ==============================================================================

ensure_provisioning() {
    # Check using variables from utils.sh (COMFYUI_ROOT_DIR)
    if [ ! -d "$COMFYUI_ROOT_DIR" ] || [ ! -f "$COMFYUI_ROOT_DIR/main.py" ]; then
        echo "============================================================"
        log_warn "ComfyUI runtime not found at: ${COMFYUI_ROOT_DIR:-/app/external/ComfyUI}"
        log_info ">>> The container is entering STANDBY mode."
        log_info ">>> Please run 'make install-oss' to provision the system."
        echo "============================================================"
        
        # Block forever to allow installation
        exec tail -f /dev/null
    fi
}

# ==============================================================================
# 3. Environment Logic
# ==============================================================================

scan_recipe_environments() {
    local envs=()
    local namespaces=("enterprise" "core")

    log_info "Scanning for available environments..."

    for ns in "${namespaces[@]}"; do
        local recipes_dir="${APP_ROOT}/config/takumi_meta/${ns}/recipes/use_cases"
        
        if [ -d "$recipes_dir" ]; then
            while IFS= read -r file; do
                if [ -f "$file" ]; then
                    local env_name
                    env_name=$(jq -r '.environment.name // empty' "$file" 2>/dev/null || true)
                    if [ -n "$env_name" ]; then
                        envs+=("$env_name")
                    fi
                fi
            done < <(find "$recipes_dir" -maxdepth 1 -name "*.json")
        fi
    done

    envs+=("takumi_standard" "foundation")
    echo "${envs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

setup_conda() {
    log_info "Initializing Conda..."
    
    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
        source /opt/conda/etc/profile.d/conda.sh
    else
        log_error "Conda system not found."
        exec tail -f /dev/null
    fi

    if [ -f "$ACTIVE_ENV_FILE" ]; then
        local last_env
        last_env=$(cat "$ACTIVE_ENV_FILE" | tr -d '[:space:]')
        if conda env list | grep -q "${last_env}"; then
            log_success "Resuming environment: ${last_env}"
            set +u; conda activate "${last_env}"; set -u
            return 0
        fi
    fi

    local candidates=($(scan_recipe_environments))
    for env_name in "${candidates[@]}"; do
        if conda env list | grep -q "${env_name}"; then
            log_success "Activating available environment: ${env_name}"
            set +u; conda activate "${env_name}"; set -u
            return 0
        fi
    done

    log_error "No suitable Conda environment found."
    log_info "Candidates were: ${candidates[*]}"
    exec tail -f /dev/null
}

# ==============================================================================
# 4. Service Orchestration
# ==============================================================================

link_bridge_extension() {
    local bridge_src="${APP_ROOT}/takumi_bridge"
    local bridge_link="${COMFYUI_CUSTOM_NODES_DIR}/ComfyUI-Takumi-Bridge"

    if [ -d "$bridge_src" ] && [ -d "$COMFYUI_CUSTOM_NODES_DIR" ]; then
        if [ ! -L "$bridge_link" ]; then
            ln -s "$bridge_src" "$bridge_link"
            log_success "Linked Takumi Bridge extension."
        fi
    fi
}

connect_brain() {
    if [[ "$BRAIN_HOST" != *"127.0.0.1"* ]] && [[ "$BRAIN_HOST" != *"localhost"* ]]; then
        log_info "Using External Brain at: $BRAIN_HOST"
        return
    fi

    if ! pgrep -x "ollama" > /dev/null; then
        log_info "Starting Local Brain (Background)..."
        ollama serve > "$OLLAMA_LOG" 2>&1 &
    fi
}

# ==============================================================================
# 5. Main Loop
# ==============================================================================

main() {
    # 1. Safety Net
    ensure_provisioning

    # --- ENTER STRICT MODE ---
    set -euo pipefail

    log_info "Takumi Engine igniting..."

    # 2. Prepare Environment
    setup_conda
    link_bridge_extension
    connect_brain

    # 3. Launch Application
    log_info "Launching ComfyUI at ${COMFYUI_ROOT_DIR}..."
    cd "$COMFYUI_ROOT_DIR"
    
    exec python main.py ${CLI_ARGS:---listen 0.0.0.0 --port $COMFY_PORT}
}

main