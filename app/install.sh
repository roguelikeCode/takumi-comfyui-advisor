#!/bin/bash

# ==============================================================================
# The Takumi's ComfyUI Installer v4.2 (Clean Flow)
# ==============================================================================

# --- Shell Environment Initialization ---
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

# --- Strict Mode ---
set -euo pipefail

# --- Import Libraries ---
source /app/lib/utils.sh       # Constants & State
source /app/lib/logger.sh      # Logging & Error Handling
source /app/lib/brain.sh       # AI Interface
source /app/lib/diagnostics.sh # Hardware Check
source /app/lib/concierge.sh   # UI / Menu
source /app/lib/installer.sh   # Core Logic

# --- Initialization ---
ensure_directories
trap 'cleanup_and_report' EXIT

# ==============================================================================
# Main Execution Engine
# ==============================================================================

main() {
    log_info "Takumi Installer Engine v4.2 starting..."

    # Fix permissions for .conda (Rootless Docker quirk)
    if [ -d "/home/takumi/.conda" ]; then
        log_info "Fixing permissions for .conda directory..."
        sudo chown -R $(id -u):$(id -g) /home/takumi/.conda
    fi

    # --- Phase 1: Preparation ---
    
    # [Fix] Isolation Mode (SKIP_BRAIN=true) check
    if [ "${SKIP_BRAIN:-false}" = "true" ]; then
        log_info "Skipping Brain setup (Isolation Mode Active)."
    else
        # 通常起動時のみ実行
        if command -v provision_brain &> /dev/null; then
            provision_brain
        fi
    fi

    if ! try_with_ai "fetch_external_catalogs" "Fetching external catalogs"; then
        log_warn "Could not fetch external catalogs. Proceeding with local files if available."
    fi

    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # --- Phase 2: User Goal Identification ---
    if [ -z "${state[use_case]}" ]; then
        run_concierge_use_case
    fi

    # --- Phase 3: Execution (Base Install) ---
    if ! run_install_flow; then
        log_error "Installation failed."
        exit 1
    fi

    # Ensure Takumi Bridge is linked
    if [ -d "/app/takumi_bridge" ]; then
        target_link="${COMFYUI_CUSTOM_NODES_DIR}/ComfyUI-Takumi-Bridge"
        if [ ! -L "$target_link" ]; then
            log_info "Linking Takumi Bridge..."
            ln -s "/app/takumi_bridge" "$target_link"
        fi
    fi

    # --- Phase 4: Smart Dependency Resolver ---
    # [Why] To consolidate requirements and install them safely (Low Memory).
    local resolver_script="/app/scripts/smart_resolver.py"
    
    if [ -f "$resolver_script" ]; then
        log_info "🛡️  Running Takumi Smart Resolver..."
        
        # Script handles resolution AND installation.
        if ! python3 "$resolver_script"; then
            log_warn "Smart Resolver finished with warnings."
        fi
    fi

    # --- Phase 5: Extensions --- 
    run_extension_hooks "post_install"

    # --- Phase 6: Finalization ---
    local recipe_path=""
    if [ -n "${state[use_case]}" ]; then
        recipe_path="${CONFIG_DIR}/takumi_meta/enterprise/recipes/use_cases/${state[use_case]}.json"
        if [ ! -f "$recipe_path" ]; then
             recipe_path="${CONFIG_DIR}/takumi_meta/core/recipes/use_cases/${state[use_case]}.json"
        fi
    fi

    # Success Report
    if command -v python3 >/dev/null; then
        python3 "${APP_ROOT}/scripts/report_failure.py" "$INSTALL_LOG" "$recipe_path"
    fi

    log_success "All processes completed successfully!"
    exit 0
}

# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@" > >(tee "$INSTALL_LOG") 2>&1
fi