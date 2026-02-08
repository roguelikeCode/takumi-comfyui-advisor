#!/bin/bash

# ==============================================================================
# Takumi Runtime Engine v2.4 (Namespace + Safety)
# ==============================================================================

# --- Import Libraries ---
if [ -f "/app/lib/utils.sh" ]; then source /app/lib/utils.sh; fi
if [ -f "/app/lib/logger.sh" ]; then source /app/lib/logger.sh; fi

# Fallback Logger
if ! command -v log_info &> /dev/null; then
    log_info() { echo "INFO: $1"; }
    log_success() { echo "SUCCESS: $1"; }
    log_warn() { echo "WARN: $1"; }
    log_error() { echo "ERROR: $1"; }
fi

# [CRITICAL] 起動初期はエラーで落ちないようにする（待機モードへ移行するため）
set +e

readonly COMFY_DIR="/app/external/ComfyUI"
readonly ACTIVE_ENV_FILE="/app/cache/.active_env"
readonly COMFY_PORT=8188

# ==============================================================================
# 1. Pre-flight Check (Safety Net)
# ==============================================================================
# 最優先: インストールされていなければ、何もせずに待機する
# これを main の先頭でやらないと、Condaロード等でエラーになり再起動ループする
check_installation_status() {
    if [ ! -d "$COMFY_DIR" ] || [ ! -f "$COMFY_DIR/main.py" ]; then
        echo "---------------------------------------------------"
        log_warn "ComfyUI not found at $COMFY_DIR"
        log_info "Container is entering STANDBY mode."
        log_info "Please run 'make install-oss' to provision this container."
        echo "---------------------------------------------------"
        
        # [STOP HERE] 永久に待機 (インストーラーの接続を待つ)
        exec tail -f /dev/null
    fi
}

# ==============================================================================
# 2. Dynamic Environment Resolution (Namespace Logic)
# ==============================================================================

detect_available_environments() {
    local envs=()
    # 検索順序: Enterprise(上書き) -> Core(基盤)
    local namespaces=("enterprise" "core")

    log_info "Scanning for available environments..."

    for ns in "${namespaces[@]}"; do
        local recipes_dir="/app/config/takumi_meta/${ns}/recipes/use_cases"
        
        if [ -d "$recipes_dir" ]; then
            while IFS= read -r file; do
                if [ -f "$file" ]; then
                    # jqで environment.name を抽出
                    local env_name
                    env_name=$(jq -r '.environment.name // empty' "$file" 2>/dev/null || true)
                    if [ -n "$env_name" ]; then
                        envs+=("$env_name")
                    fi
                fi
            done < <(find "$recipes_dir" -maxdepth 1 -name "*.json")
        fi
    done

    # フォールバック
    envs+=("takumi_standard" "foundation")
    
    # 重複排除して出力
    echo "${envs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

activate_conda_environment() {
    log_info "Initializing Conda environment..."
    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
        source /opt/conda/etc/profile.d/conda.sh
    else
        log_error "Conda not found at /opt/conda"
        # 待機モードへ
        exec tail -f /dev/null
    fi

    # Strategy 1: Last used environment
    if [ -f "$ACTIVE_ENV_FILE" ]; then
        local last_env
        last_env=$(cat "$ACTIVE_ENV_FILE" | tr -d '[:space:]')
        if conda env list | grep -q "${last_env}"; then
            log_success "Resuming environment: ${last_env}"
            set +u; conda activate "${last_env}"; set -u
            return 0
        fi
    fi

    # Strategy 2: Scan recipes (Namespace Aware)
    local candidates=($(detect_available_environments))
    
    for env_name in "${candidates[@]}"; do
        if conda env list | grep -q "${env_name}"; then
            log_success "Activating available environment: ${env_name}"
            set +u; conda activate "${env_name}"; set -u
            return 0
        fi
    done

    log_error "No suitable Conda environment found."
    log_info "Candidates were: ${candidates[*]}"
    # エラーで落とさず待機（デバッグ用）
    exec tail -f /dev/null
}

# ==============================================================================
# 3. Service Logic
# ==============================================================================

setup_bridge_node() {
    local nodes_dir="${COMFY_DIR}/custom_nodes"
    local target_link="${nodes_dir}/ComfyUI-Takumi-Bridge"
    local source_dir="/app/takumi_bridge"

    if [ -d "$nodes_dir" ] && [ -d "$source_dir" ]; then
        if [ ! -L "$target_link" ]; then
            ln -s "$source_dir" "$target_link"
            log_success "Linked Takumi Bridge."
        fi
    fi
}

start_brain_service() {
    local target_host="${OLLAMA_HOST:-http://127.0.0.1:11434}"
    
    # 外部接続なら接続確認のみ
    if [[ "$target_host" != *"127.0.0.1"* ]] && [[ "$target_host" != *"localhost"* ]]; then
        log_info "Using External Brain at: $target_host"
        return
    fi

    # ローカル起動
    if ! pgrep -x "ollama" > /dev/null; then
        log_info "Starting Local Brain..."
        ollama serve > /app/logs/ollama.log 2>&1 &
    fi
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    # 1. 存在確認 (なければ待機)
    check_installation_status

    # ここから厳格モード
    set -euo pipefail

    log_info "Takumi Runtime Engine Starting..."

    # 2. 環境有効化
    activate_conda_environment

    # 3. コンポーネント接続
    setup_bridge_node
    start_brain_service

    # 4. ComfyUI起動
    log_info "Launching ComfyUI..."
    cd "$COMFY_DIR"
    python main.py ${CLI_ARGS:---listen 0.0.0.0 --port 8188}
}

main