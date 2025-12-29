#!/bin/bash

# [Why] To centrally manage paths and state variables shared across the project.
# [What] Defines directory paths and initializes global state arrays.

# --- File Paths (In Docker) ---
readonly APP_ROOT="/app"
readonly CACHE_DIR="${APP_ROOT}/cache"
readonly CONFIG_DIR="${APP_ROOT}/config"
readonly EXTERNAL_DIR="${APP_ROOT}/external"
readonly LOG_DIR="${APP_ROOT}/logs"

readonly ACTIVE_ENV_FILE="${APP_ROOT}/cache/.active_env"
readonly HISTORY_FILE="${APP_ROOT}/cache/.install_history"
readonly INSTALL_LOG="${LOG_DIR}/install.log"

# --- Global Configuration (Defaults) ---
# [Why] To prevent "unbound variable" errors when strict mode (-u) is active.
# [What] Set defaults if environment variables are missing.
export DEV_MODE="${TAKUMI_DEV_MODE:-false}"
export TAKUMI_PRIVACY_LEVEL="${TAKUMI_PRIVACY_LEVEL:-2}"

# --- Global State Declaration ---
# [Note] Using associative arrays (Requires Bash 4.0+)
declare -A state=(
    ["history"]=""
    ["use_case"]=""
    ["use_case_env"]=""
    ["detected_accelerator"]=""
    ["detected_cuda_major"]=""
)

# [Why] To ensure the necessary directory structure exists before execution.
# [What] Creates log, cache, and external directories if they don't exist.
ensure_directories() {
    mkdir -p "$LOG_DIR" "$CACHE_DIR" "$EXTERNAL_DIR"
}