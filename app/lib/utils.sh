#!/bin/bash

# --- Include Guard (Critical Fix) ---
# [Why] To prevent "readonly variable" errors when sourced multiple times.
if [ -n "${UTILS_SH_LOADED:-}" ]; then
    return 0
fi
readonly UTILS_SH_LOADED=true

# [Why] To centrally manage paths and state variables shared across the project.
# [What] Defines directory paths and initializes global state arrays.

# --- File Paths (In Docker) ---
readonly APP_ROOT="/app"
readonly CACHE_DIR="${APP_ROOT}/cache"
readonly CONFIG_DIR="${APP_ROOT}/config"
readonly EXTERNAL_DIR="${APP_ROOT}/external"
readonly LOG_DIR="${APP_ROOT}/logs"
COMFYUI_ROOT_DIR="${EXTERNAL_DIR}/ComfyUI"
COMFYUI_CUSTOM_NODES_DIR="${COMFYUI_ROOT_DIR}/custom_nodes"

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

# [Why] Resolve the path of the configuration file (Enterprise preferred)
# [Input] $1: Relative paths (e.g. infra/environments/cuda_12_4.yml)
# [Output] Absolute path (empty if not found)
resolve_meta_path() {
    local rel_path="$1"
    local ent_path="/app/config/takumi_meta/enterprise/$rel_path"
    local core_path="/app/config/takumi_meta/core/$rel_path"

    if [ -f "$ent_path" ]; then
        echo "$ent_path"
    elif [ -f "$core_path" ]; then
        echo "$core_path"
    else
        echo "" # Not found
    fi
}

# [Why] Resolve the actual file path from the recipe name (Ent -> Core)
# [Input] $1: recipe_slug (e.g. "wan_video_2_2")
# [Output] Absolute path to json file
find_use_case_recipe_path() {
    local slug="$1"
    local filename="${slug}.json"
    
    local ent_path="${CONFIG_DIR}/takumi_meta/enterprise/recipes/use_cases/${filename}"
    local core_path="${CONFIG_DIR}/takumi_meta/core/recipes/use_cases/${filename}"

    if [ -f "$ent_path" ]; then
        echo "$ent_path"
    elif [ -f "$core_path" ]; then
        echo "$core_path"
    else
        return 1
    fi
}