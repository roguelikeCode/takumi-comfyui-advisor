# ==============================================================================
# The Takumi's ComfyUI Installer v3.2 (Single-Attempt Engine)
#
# This script executes a single, guided installation attempt within a Docker
# container. It is designed to be orchestrated by an external tool (e.g., Makefile)
# that handles retry loops.
#
# It reports its result via exit codes:
#   - 0: Success
#   - 1: Generic failure, retry possible
#   - 125: Failure, user chose to report to The Takumi (final exit)
# ==============================================================================

#!/bin/bash

# ==============================================================================
# The Takumi's ComfyUI Installer v4.0 (Modularized)
# ==============================================================================

# --- Shell Environment Initialization ---
# [Why] To enable 'conda' commands in non-interactive shells.
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

# --- Strict Mode ---
set -euo pipefail

# --- Import Libraries ---
# [Why] To load the separated logic modules.
# [Note] Paths are absolute inside the Docker container (/app/...).
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
    log_info "Takumi Installer Engine v4.0 starting..."

    # Change permissions of .conda directory (owned by root due to volume mount) to takumi user
    if [ -d "/home/takumi/.conda" ]; then
        log_info "Fixing permissions for .conda directory..."
        sudo chown -R $(id -u):$(id -g) /home/takumi/.conda
    fi

    # --- Phase 1: Preparation ---
    # Now 'try_with_ai' is available via source /app/lib/brain.sh
    if ! try_with_ai "fetch_external_catalogs" "Fetching external catalogs"; then
        log_warn "Could not fetch external catalogs. Proceeding with local files if available."
    fi

    # Now 'build_merged_catalog' is available via source /app/lib/installer.sh
    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # --- Phase 2: User Goal Identification ---
    if [ -z "${state[use_case]}" ]; then
        run_concierge_use_case
    fi

    # --- Phase 3: Execution ---
    if ! run_install_flow; then
        log_error "Installation failed."
        exit 1
    fi

    # Ensure Takumi Bridge is linked during install
    if [ -d "/app/takumi_bridge" ]; then
        target_link="${COMFYUI_CUSTOM_NODES_DIR}/ComfyUI-Takumi-Bridge"
        if [ ! -L "$target_link" ]; then
            log_info "Linking Takumi Bridge..."
            ln -s "/app/takumi_bridge" "$target_link"
        fi
    fi

    # --- Phase 4: [Extension Slot] enterprise / Custom Hooks --- 
    run_extension_hooks "post_install"

    # --- Phase 5: Finalization ---
    log_success "All processes completed successfully!"
    exit 0
}

# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Log everything to file while showing in console
    main "$@" > >(tee "$INSTALL_LOG") 2>&1
fi