#!/bin/bash

# ==============================================================================
# The Takumi's ComfyUI Installer v4.2 (Elegant Flow)
# [Why] To provide a robust, single-attempt installation engine for ComfyUI.
# [What] Orchestrates environment setup, dependency resolution, and telemetry.
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
# Sub-Routines (Encapsulation)
# ==============================================================================

# [Why] Rootless Docker maps the host user to root inside, creating permission conflicts for Conda.
# [What] Restores ownership of the Conda directory to the unprivileged 'takumi' user.
fix_conda_permissions() {
    if [ -d "/home/takumi/.conda" ]; then
        log_info "Fixing permissions for .conda directory..."
        sudo chown -R "$(id -u)":"$(id -g)" /home/takumi/.conda
    fi
}

# [Why] To seamlessly integrate the Takumi Bridge into the ComfyUI ecosystem.
# [What] Creates a symbolic link from the app directory to the ComfyUI custom_nodes directory.
link_takumi_bridge() {
    local bridge_src="/app/takumi_bridge"
    local bridge_link="${COMFYUI_CUSTOM_NODES_DIR}/ComfyUI-Takumi-Bridge"

    if [ -d "$bridge_src" ]; then
        if [ ! -L "$bridge_link" ]; then
            log_info "Linking Takumi Bridge..."
            ln -s "$bridge_src" "$bridge_link"
        fi
    fi
}

# [Why] To consolidate requirements and install them safely with low memory overhead.
# [What] Executes the Python-based smart dependency resolver within the target Conda environment.
run_smart_resolver() {
    local resolver_script="/app/scripts/smart_resolver.py"
    
    if [ -f "$resolver_script" ]; then
        log_info "🛡️  Running Takumi Smart Resolver..."
        (
            source /opt/conda/etc/profile.d/conda.sh
            set +u
            conda activate "${state[use_case_env]}"
            set -u
            # Use 'python' to strictly invoke Conda's internal shim
            if ! python "$resolver_script"; then
                log_warn "Smart Resolver finished with warnings."
            fi
        )
    fi
}

# [Why] To finalize the installation process and log the outcome.
# [What] Resolves the exact recipe path used and sends an installation receipt via the telemetry script.
finalize_installation() {
    local recipe_path=""
    if [ -n "${state[use_case]:-}" ]; then
        # [Zero-State] Direct lookup in volatile memory
        recipe_path="/app/cache/takumi_meta/recipes/use_cases/${state[use_case]}.json"
    fi

    # Trigger success report
    if command -v python3 >/dev/null; then
        python3 "${APP_ROOT}/scripts/report_failure.py" "$INSTALL_LOG" "$recipe_path"
    fi
}

# ==============================================================================
# Main Execution Engine
# ==============================================================================

main() {
    log_info "Takumi Installer Engine v4.2 starting..."

    fix_conda_permissions

    # --- Phase 1: Preparation ---
    if type takumi_registry &>/dev/null; then
        takumi_registry
    fi
    
    if ! try_with_ai "fetch_external_catalogs" "Fetching external catalogs"; then
        log_warn "Could not fetch external catalogs. Proceeding with local files if available."
    fi

    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # --- Phase 2: User Goal Identification ---
    # Safe variable expansion to prevent 'unbound variable' error under strict mode
    if [ -z "${state[use_case]:-}" ]; then
        run_concierge_use_case
    fi

    # --- Phase 3: Base Installation ---
    if ! run_install_flow; then
        log_error "Installation failed."
        exit 1
    fi

    link_takumi_bridge

    # --- Phase 4: Dependency Resolution ---
    run_smart_resolver

    # --- Phase 5: Extensions --- 
    run_extension_hooks "post_install"

    # --- Phase 6: Finalization ---
    finalize_installation

    log_success "All processes completed successfully!"
    exit 0
}

# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@" > >(tee "$INSTALL_LOG") 2>&1
fi