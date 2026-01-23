#!/bin/bash

# --- Include Guard ---
# [Why] To prevent 'readonly variable' errors when sourced multiple times.

if [ -n "${LOGGER_SH_LOADED:-}" ]; then
    return 0
fi
readonly LOGGER_SH_LOADED=true

# --- Constants: Colors ---
# [Why] To unify log formats/colors and handle errors/telemetry centrally.
# [What] Provides logging functions, color definitions, and the error trap handler.

readonly COLOR_BLUE='\033[1;36m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# --- Logging Functions ---

# [Input] $1: message
log_info() { echo -e "${COLOR_BLUE}INFO: $1${COLOR_RESET}"; }
log_success() { echo -e "${COLOR_GREEN}SUCCESS: $1${COLOR_RESET}"; }
log_warn() { echo -e "${COLOR_YELLOW}WARN: $1${COLOR_RESET}"; }
log_error() { echo -e "${COLOR_RED}ERROR: $1${COLOR_RESET}"; }

# --- Error Handling & Telemetry ---

# [Why] To automatically collect and send diagnostics when installation fails.
# [What] Checks the exit code. If non-zero, triggers the Python reporting script.

# [Input] Global: $TAKUMI_PRIVACY_LEVEL, $INSTALL_LOG, $APP_ROOT, $CONFIG_DIR, $state[use_case]
cleanup_and_report() {
    local exit_code=$?
    
    # Do nothing if successful
    if [ $exit_code -eq 0 ]; then
        return
    fi

    echo ""
    log_error "Installation failed with exit code $exit_code."

    # Privacy Guard (Using :- to be safe against unbound variables)
    if [ "${TAKUMI_PRIVACY_LEVEL:-}" = "0" ]; then
        echo ">>> [Privacy] Telemetry disabled (Level 0)."
        exit $exit_code
    fi
    
    # Resolve recipe path for the report
    local recipe_path=""
    if [ -n "${state[use_case]}" ]; then
        recipe_path="${CONFIG_DIR}/takumi_meta/core/recipes/use_cases/${state[use_case]}.json"
    fi

    # Trigger failure report
    if command -v python3 >/dev/null; then
        python3 "${APP_ROOT}/scripts/report_failure.py" "$INSTALL_LOG" "$recipe_path"
    fi
    
    exit $exit_code
}