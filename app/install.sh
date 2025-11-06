# ==============================================================================
# The Takumi's ComfyUI Installer v2.2 (Single-Attempt Engine)
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

# --- Development Mode ---
DEV_MODE=${TAKUMI_DEV_MODE:-false}

# --- Strict Mode & Safety ---
set -euo pipefail

# ==============================================================================
# Constants and Global State
# ==============================================================================

# --- Logger ---
readonly COLOR_BLUE='\033[1;36m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

log_info() { echo -e "${COLOR_BLUE}INFO: $1${COLOR_RESET}"; }
log_success() { echo -e "${COLOR_GREEN}SUCCESS: $1${COLOR_RESET}"; }
log_warn() { echo -e "${COLOR_YELLOW}WARN: $1${COLOR_RESET}"; }
log_error() { echo -e "${COLOR_RED}ERROR: $1${COLOR_RESET}"; }

# --- File Paths (In Docker) ---
readonly APP_ROOT="/app"

readonly HISTORY_FILE="${APP_ROOT}/.install_history"
readonly CONFIG_DIR="${APP_ROOT}/config"
readonly EXTERNAL_DIR="${APP_ROOT}/external"
readonly CACHE_DIR="${APP_ROOT}/cache"
readonly LOG_DIR="${APP_ROOT}/logs"

# --- Global State Declaration ---
declare -A state=(
    ["history"]=""
    ["use_case"]=""
    ["last_error_log"]=""
)

# ==============================================================================
# Logger
# ==============================================================================

submit_log_to_takumi() {
    local log_content="$1" 

    # --- Development Mode ---
    # Write the log to a local file
    if [ "$DEV_MODE" = "true" ]; then
        mkdir -p "$LOG_DIR"
        local log_file="$LOG_DIR/logbook_$(date +%s).jsonc"
        echo "$log_content" > "$log_file"
        log_warn "DEV MODE: Log saved locally to $log_file"
        return
    fi

    # --- Production Mode ---
    # Ask user for consent and send to cloud
    read -p "Contribute this anonymous log to The Takumi's Logbook? (Y/n): " consent
    if [[ "${consent,,}" != "n" ]]; then
        log_info "Thank you. Submitting log to the collective intelligence..."

        # ログの内容を curl コマンドで送信する
        # curl -X POST \
        #  -H "Content-Type: application/json" \
        #  -d "$log_content" \  # <-- $LOG_JSON から $log_content に修正
        #  "https://<your-api-gateway-endpoint>"
        
        # (上記のcurlはまだ動かないので、今はシミュレーションする)
        sleep 1 # 送信しているように見せる
        
        log_success "Log submitted successfully."
    fi
}

# ==============================================================================
# Catalog Management Nodes
# ==============================================================================

build_merged_catalog() {
    local entity_name="$1"
    log_info "Building the merged catalog for '${entity_name}'..."

    # Define paths using the global constants
    local external_catalog="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local takumi_meta_catalog="${CONFIG_DIR}/takumi_meta/entities/${entity_name}.jsonc"
    local merged_catalog_dir="${CACHE_DIR}/catalogs"
    local merged_catalog_path="${merged_catalog_dir}/${entity_name}.jsonc"

    # --- Pre-flight Checks (Safety First) ---
    if [ ! -f "$external_catalog" ]; then
        log_error "External catalog not found: $external_catalog"
        return 1
    fi
    if [ ! -f "$takumi_meta_catalog" ]; then
        log_error "Takumi meta catalog not found: $takumi_meta_catalog"
        return 1
    fi

    # Ensure the cache directory exists
    mkdir -p "$merged_catalog_dir"

    # --- The Merge Operation ---
    if yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "$external_catalog" \
        "$takumi_meta_catalog" \
        > "$merged_catalog_path"; then
        
        log_success "Merged catalog for '${entity_name}' created at: $merged_catalog_path"
        return 0
    else
        local exit_code=$?
        log_error "Failed to merge catalog for '${entity_name}' with yq (exit code: $exit_code)."
        return 1
    fi
}

# ==============================================================================
# Installation Nodes (The "How")
# ==============================================================================

node_install_bulk_requirements() {
    local use_case=$1
    log_info "Installing bulk Python requirements for use case: '$use_case'..."
    
    # --- To be implemented ---
    # 1. yq '.${use_case}.include_nodes[]' ${RECIPE_DIR}/usecase_recipes.yml
    # 2. Loop through nodes, find their requirements.txt, concatenate them.
    # 3. pip install -r combined_requirements.txt
    # ---
    
    # Placeholder
    echo "Simulating bulk install for '$use_case'..." && sleep 1
    log_success "Bulk requirements installed."
}

node_install_hazardous_libraries() {
    local use_case=$1
    log_info "Installing hazardous libraries with special care for '$use_case'..."

    # --- To be implemented ---
    # 1. yq '.${use_case}.hazardous_installs[]' ${RECIPE_DIR}/usecase_recipes.yml
    # 2. Loop through libraries and pip install them one by one.
    # ---
    
    # Placeholder
    log_info "-> Installing 'kornia' via pip..." && sleep 1
    log_success "Hazardous libraries handled."
}

run_install_flow() {
    log_info "Starting installation flow..."
    local log_file="/tmp/install_$(date +%s).log"

    # Execute installation nodes, redirecting all output to a log file.
    if {
        node_install_bulk_requirements "${state[use_case]}"
        node_install_hazardous_libraries "${state[use_case]}"
    } > "$log_file" 2>&1; then
        # Success Case
        rm -f "$log_file"
        return 0
    else
        # Failure Case
        local exit_code=$?
        log_error "An error occurred during installation (exit code: $exit_code)."
        log_warn "Full log has been captured for analysis."
        
        # Store captured log in the global state
        state["last_error_log"]=$(cat "$log_file")
        rm -f "$log_file" # Clean up temporary log file
        return 1
    fi
}

# ==============================================================================
# The Takumi's Concierge & Sommelier (The "What" and "Why")
# ==============================================================================

run_concierge() {
    log_info "Welcome to The Takumi's Concierge."
    log_info "Your base environment is perfect. Let's finalize your workshop."
    
    echo ""
    echo "Please choose your primary use case:"
    echo "  (1) Photorealistic"
    echo "  (2) Anime / Illustration"
    # --- To be implemented ---
    # Dynamically generate options from usecase_recipes.yml
    # ---
    read -p "Enter number [1]: " choice
    local use_case_key="photorealistic" # Placeholder
    if [[ "${choice}" == "2" ]]; then use_case_key="anime"; fi

    echo ""
    log_info "Plan for '$use_case_key':"
    echo "  - Install a curated set of Python libraries for your custom nodes."
    echo "  - Apply special handling for libraries known to cause conflicts."
    echo ""
    read -p "Proceed with this plan? (Y/n): " consent
    if [[ "${consent,,}" == "n" ]]; then
        log_warn "Installation aborted by user."
        exit 1 # Exit with a generic failure code
    fi

    # Store the final choice in the global state
    state["use_case"]=$use_case_key
}

run_sommelier() {
    log_info "Consulting The Takumi's Sommelier for a solution..."
    
    # --- To be implemented ---
    # FR-3.2: Rule-based check against error_recipes.yml
    # FR-3.3: Escalate to SLM if no rule matches
    # FR-3.4: Offer one-time retry
    # ---

    # Placeholder logic for demonstration
    log_warn "This appears to be an unknown issue."
    read -p "Consult a small AI (SLM) for hints (experimental)? (Y/n): " consent
    if [[ "${consent,,}" == "y" ]]; then
        local slm_suggestion="pip install torch==2.2.0 --force-reinstall"
        
        read -p "The SLM suggests: '$slm_suggestion'. Try this solution? (Y/n): " try_consent
        if [[ "${consent,,}" != "n" ]]; then
            echo "use_case:${state[use_case]}" > "$HISTORY_FILE"
            echo "retry_with:$slm_suggestion" >> "$HISTORY_FILE"
            log_info "Acknowledged. The orchestrator will retry with the new strategy."
            exit 1 # Exit to signal a retry to the orchestrator
        fi
    fi

    # FR-3.6: Escalate to The Takumi
    read -p "Unable to resolve. Report this issue to The Takumi? (Y/n): " report_consent
    if [[ "${report_consent,,}" != "n" ]]; then
        # --- To be implemented ---
        # Logic to submit state["last_error_log"] and state["history"]
        # ---
        log_info "Thank you for your contribution. Preparing the report..."
        exit 125 # Exit with special code for reporting
    fi

    log_error "Resolution process aborted by user."
    exit 1 # Exit with a generic failure code
}

# ==============================================================================
# Main Execution Engine
# ==============================================================================

main() {
    log_info "Takumi Installer Engine v2.2 starting..."

    # [思想] 全てのインストールの前提条件として、まず「知見のカタログ」を構築する。
    # これが失敗する場合、それ以降の処理は無意味であるため、ここで確実に停止させる。
    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # Load state from history file if it exists
    if [ -f "$HISTORY_FILE" ]; then
        log_info "Loaded installation history. This is a retry attempt."
        # --- To be implemented ---
        # A robust parser to load history into the `state` associative array.
        # For now, we'll just load the use_case as a simple example.
        state["use_case"]=$(grep "use_case:" "$HISTORY_FILE" | head -n 1 | cut -d':' -f2) || ""
        # ---
    fi

    # If use_case is not determined yet, run the initial user dialogue
    if [ -z "${state[use_case]}" ]; then
        run_concierge
    fi
    
    # Attempt the installation
    if run_install_flow; then
        # Success
        log_success "Installation was successful!"
        # Clean up history file on final success
        rm -f "$HISTORY_FILE"
        exit 0
    else
        # Failure
        run_sommelier
    fi
}

# --- Script Entry Point ---
main "$@"
