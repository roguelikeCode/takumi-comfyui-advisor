#!/bin/bash
# ==============================================================================
# Takumi Container Entrypoint (The Gatekeeper)
#
# [Role] Root Initializer
# [Responsibility]
#   1. Prepare writable directories (Pre-flight mkdir)
#   2. Fix volume permissions (Runtime Chown)
#   3. Drop privileges and execute command (Handover)
# ==============================================================================
set -e

# --- Configuration ---
readonly APP_USER="takumi"
readonly APP_GROUP="takumi"

# [Config] Directories that must exist and be writable by the app user
readonly WRITABLE_TARGETS=(
    "/app/cache"
    "/app/external"
    "/app/logs"
    "/app/storage"
    "/app/temp"
    "/home/${APP_USER}"
)

# --- Helper Functions ---
log_info() { echo ">>> [Entrypoint] $1"; }

ensure_directories() {
    log_info "Ensuring directory structure..."
    for dir in "${WRITABLE_TARGETS[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
}

fix_permissions() {
    log_info "Fixing volume permissions (Root -> ${APP_USER})..."
    chown -R "${APP_USER}:${APP_GROUP}" "${WRITABLE_TARGETS[@]}"
}

handover() {
    log_info "Dropping privileges. Handing over to: $*"
    exec gosu "${APP_USER}" "$@"
}

# --- Main Execution ---
main() {
    ensure_directories
    fix_permissions
    handover "$@"
}

main "$@"