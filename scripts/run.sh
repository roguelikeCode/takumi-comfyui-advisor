#!/bin/bash

# ==============================================================================
# Takumi Application Runner
#
# [Why] To orchestrate the runtime environment inside the Docker container.
# [What] Activates Conda, links extensions, starts background services (AI/Dashboard), and launches ComfyUI.
# ==============================================================================

# --- Import Libraries ---
source /app/lib/utils.sh
source /app/lib/logger.sh

# --- Strict Mode ---
set -euo pipefail

# --- Configuration ---
# Prioritized list of environments to look for
readonly TARGET_ENVS=("animatediff_env" "magic_clothing_env" "foundation")
readonly COMFY_PORT=8188

# ==============================================================================
# [1] Environment Management
# ==============================================================================

# [Why] To automatically select the installed environment without hardcoding.
# [What] Checks conda env list and activates the first match.
# [Note] Conda activation scripts may use undefined variables, so temporarily disable "set -u" (undefined variable error)
activate_conda_environment() {
    log_info "Initializing Conda environment..."
    source /opt/conda/etc/profile.d/conda.sh

    # Priority 1: Check for the last installed environment to ensure consistency.
    local active_env_file="/app/.active_env"
    if [ -f "$active_env_file" ]; then
        local last_env
        last_env=$(cat "$active_env_file" | tr -d '[:space:]')
        
        if conda env list | grep -q "${last_env}"; then
            log_success "Activating last used environment: ${last_env}"
            
            # Disable strict mode temporarily to avoid Conda's unbound variable errors
            # Conda activation scripts often reference unbound variables (MKL_INTERFACE_LAYER)
            set +u
            conda activate "${last_env}"
            set -u
            
            return 0
        fi
    fi

    # Priority 2: Fallback to the predefined list if no active env record exists.
    for env_name in "${TARGET_ENVS[@]}"; do
        if conda env list | grep -q "${env_name}"; then
            log_success "Found active environment: ${env_name}"
            
            # Disable strict mode temporarily
            set +u
            conda activate "${env_name}"
            set -u
            
            return 0
        fi
    done

    # If the environment is not found, an error occurs.
    log_error "No suitable Conda environment found."
    log_warn "Expected one of: ${TARGET_ENVS[*]}"
    return 1
}


# ==============================================================================
# [2] Service Managers
# ==============================================================================

# [Why] To expose the Chat UI extension to ComfyUI.
# [What] Creates a symbolic link from the source code to the ComfyUI custom_nodes folder.
setup_bridge_node() {
    local target_link="/app/ComfyUI/custom_nodes/ComfyUI-Takumi-Bridge"
    local source_dir="/app/takumi_bridge"

    log_info "Configuring Takumi Bridge..."

    if [ -d "$source_dir" ]; then
        if [ ! -L "$target_link" ]; then
            ln -s "$source_dir" "$target_link"
            log_success "Linked Takumi Bridge to custom_nodes."
        else
            log_info "  -> Bridge already linked."
        fi
    else
        log_warn "Takumi Bridge source not found at $source_dir"
    fi
}

# [Why] To provide the AI backend for the Chat UI.
# [What] Starts Ollama in the background.
start_brain_service() {
    log_info "Starting The Brain (Ollama)..."
    
    # Start in background
    ollama serve > /app/logs/ollama.log 2>&1 &
    
    # Wait for wakeup
    log_info "  -> Waiting for neural network to initialize..."
    sleep 3
}

# ==============================================================================
# [3] Main Execution
# ==============================================================================

main() {
    log_info "Takumi Runtime Engine Starting..."

    # 1. Setup Environment
    activate_conda_environment

    # 2. Setup Components
    setup_bridge_node

    # 3. Start Background Services
    # [Important] Kill background jobs (Ollama/Streamlit) when this script exits
    terminate_services() {
        # Get list of background job IDs
        local pids=$(jobs -p)
        
        if [ -n "$pids" ]; then
            # Kill processes and suppress errors if they are already dead
            kill $pids >/dev/null 2>&1 || true
        fi
    }
    
    # Register the trap
    trap 'terminate_services' EXIT
    
    start_brain_service

    # [Extension Slot] Launch Commercial Services
    # If there are any extension scripts that should be run at startup, run them in the background
    if [ -f "/app/extensions/hooks/on_boot/run.sh" ]; then
        log_info "🚀 Launching Commercial Extension..."
        bash "/app/extensions/hooks/on_boot/run.sh" &
    fi

    # 4. Launch Main Application (Blocking)
    log_info "Launching ComfyUI..."
    
    cd /app/ComfyUI
    python main.py --listen 0.0.0.0 --port "$COMFY_PORT"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi