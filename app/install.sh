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

fetch_external_catalogs() {
    log_info "Fetching latest external catalogs..."
    
    local manager_list_url="https://raw.githubusercontent.com/Comfy-Org/ComfyUI-Manager/main/custom-node-list.json"
    local external_catalog_path="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local external_catalog_dir
    external_catalog_dir=$(dirname "$external_catalog_path")

    # ディレクトリが存在しない場合は作成する
    mkdir -p "$external_catalog_dir"

    # wgetコマンドでファイルをダウンロードする
    if wget --quiet -O "$external_catalog_path" "$manager_list_url"; then
        log_success "Successfully downloaded 'comfyui-manager/custom-node-list.json'."
        return 0
    else
        log_error "Failed to download 'comfyui-manager/custom-node-list.json'."
        log_warn "If you are offline, please ensure the file exists at: $external_catalog_path"
        return 1
    fi
}

build_merged_catalog() {
    local entity_name="$1"
    log_info "Building the merged catalog for '${entity_name}'..."

    local yq_command="yq"

    # Define paths using the global constants
    local merged_catalog_dir="${CACHE_DIR}/catalogs"

    local external_catalog="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local takumi_meta_catalog="${CONFIG_DIR}/takumi_meta/entities/${entity_name}_meta.json"
    local merged_catalog_path="${merged_catalog_dir}/${entity_name}_merged.json"

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

    # --- The Merge & Transform Operation ---
    if "$yq_command" eval-all --output-format json --prettyPrint \
        'select(fileIndex == 0) * select(fileIndex == 1)' \
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

combine_foundation_environment() {
    log_info "Combining components to build your 'foundation' environment..."
    
    # stateに保存された選択済みのコンポーネントを取得
    local core_tools_yml="${CONFIG_DIR}/foundation_components/${state[selected_core]}.yml"
    local python_yml="${CONFIG_DIR}/foundation_components/python/${state[selected_python]}.yml"
    local accelerator_yml="${CONFIG_DIR}/foundation_components/accelerator/${state[selected_accelerator]}.yml"

    # 全ての部品ファイルが存在するか、最後の安全確認
    if ! { [ -f "$core_tools_yml" ] && [ -f "$python_yml" ] && [ -f "$accelerator_yml" ]; }; then
        log_error "One or more required component files are missing. Cannot build environment."
        echo "Checked paths:"
        echo "  - $core_tools_yml"
        echo "  - $python_yml"
        echo "  - $accelerator_yml"
        return 1
    fi

    # conda env createコマンドを動的に組み立てて実行
    if . ${CONDA_DIR}/etc/profile.d/conda.sh && \
        conda env create \
            --file "$core_tools_yml" \
            --file "$python_yml" \
            --file "$accelerator_yml"; then
        
        log_success "Foundation environment built successfully."
        # 成功の証として、履歴ファイルに構成を記録
        echo "foundation_accelerator:${state[selected_accelerator]}" > "$HISTORY_FILE"
        echo "foundation_python:${state[selected_python]}" >> "$HISTORY_FILE"
        return 0
    else
        log_error "Failed to build the foundation environment."
        return 1
    fi
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
# Environment Diagnostics Node
# ==============================================================================

detect_gpu_environment() {
    log_info "Diagnosing your hardware environment..."
    
    # nvidia-smiコマンドが存在し、かつ実行可能かチェック
    if command -v nvidia-smi &> /dev/null; then
        # nvidia-smiコマンドを実行し、出力を変数に格納
        local smi_output
        smi_output=$(nvidia-smi)

        # 出力からCUDAのバージョンを正規表現で抽出
        if [[ $smi_output =~ CUDA\ Version:\ ([0-9]+\.[0-9]+) ]]; then
            # マッチした部分（例: "12.4"）を取得
            local cuda_version="${BASH_REMATCH[1]}"
            local cuda_major_version="${cuda_version%%.*}" # ピリオドより前 (例: "12")
            
            log_success "NVIDIA GPU detected. CUDA Driver Version: $cuda_version"
            
            # 診断結果をグローバルな連想配列 'state' に格納
            state["detected_cuda_major"]=$cuda_major_version
            state["detected_accelerator"]="cuda"
            return 0
        fi
    fi
    
    # nvidia-smiが見つからない、またはCUDAバージョンを抽出できなかった場合
    log_warn "No compatible NVIDIA GPU with CUDA drivers found."
    log_info "Proceeding with CPU-only configuration."
    state["detected_accelerator"]="cpu"
    return 0
}

# ==============================================================================
# The Takumi's Concierge & Sommelier (The "What" and "Why")
# ==============================================================================

run_concierge_foundation() {

    log_info "Welcome to The Takumi's Foundation Concierge."
    log_info "First, we will build the essential 'foundation' for your workshop."
    
    # Hardware diagnostics
    if ! detect_gpu_environment; then
        log_error "Failed to diagnose hardware environment. Cannot proceed."
        exit 1
    fi

    # Environmental component proposals
    local accelerator_component="cpu"
    # If CUDA is detected, select the component that matches the major version
    if [[ "${state[detected_accelerator]}" == "cuda" ]]; then
        accelerator_component="cuda-${state[detected_cuda_major]}"
    fi

    echo ""
    log_info "Based on our diagnosis, we propose the following foundation:"
    echo "  - Core Tools:      git, pip, etc."
    echo "  - Python Version:  3.12 (Official ComfyUI recommendation)"
    echo "  - Accelerator:     ${accelerator_component} (Optimized for your system)"
    echo ""

    # Safety equipment
    local component_path="${CONFIG_DIR}/foundation_components/accelerator/${accelerator_component}.yml"
    if [ ! -f "$component_path" ]; then
        log_error "Configuration for your accelerator ('${accelerator_component}') is not available."
        log_warn "There is no file yet. Falling back to CPU-only configuration."
        accelerator_component="cpu"
    fi
    
    read -p "Proceed with building this foundation? [Y/n]: " consent
    if [[ "${consent,,}" == "n" ]]; then
        log_warn "Installation aborted by user."
        exit 1
    fi

    # Save the user's selected configuration in 'state'
    state["selected_accelerator"]=$accelerator_component
    state["selected_python"]="3.12"
    state["selected_core"]="core-tools"
}

run_concierge_use_case() {
    log_info "Your foundation is perfect. Now, let's select your specialized tools."
    
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
    log_info "Takumi Installer Engine v3.0 starting..."

    # --- Phase 1: Preparation ---
    # 取得に失敗しても、ローカルにファイルがあれば続行可能なので、警告に留める
    if ! fetch_external_catalogs; then
        log_warn "Could not fetch external catalogs. Proceeding with local files if available."
    fi

    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # --- Phase 2: Foundation Installation ---
    # Load state from history file if it exists
    if [ -f "$HISTORY_FILE" ]; then
        log_info "Loaded installation history. Foundation is already built."
        # ---
        # A robust parser to load history into the `state` associative array.
        while IFS=':' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                state["$key"]="$value"
            fi
        done < "$HISTORY_FILE"
    else
        # 履歴ファイルがない場合、初回実行とみなし、Conciergeと環境構築を実行
        run_foundation_concierge
        # 環境構築に失敗した場合、Sommelierに助けを求める
        if ! combine_foundation_environment; then
            run_sommelier
            exit 1
        fi
    fi

    # --- ここから、ユースケース環境の追加インストールフェーズが始まる---
    # If use_case is not determined yet, run the initial user dialogue
    log_info "Foundation is ready. Proceeding to use-case selection."
    if [ -z "${state[use_case]}" ]; then
        run_use_case_concierge
    fi
    
    # Attempt the installation
    if ! run_install_flow; then
        run_sommelier; exit 1;
    fi

    # --- Finalization ---
    log_success "All processes completed successfully!"
    # 成功したら、次の再実行でPhase 3から始められるように、use_caseの選択だけを履歴に残すなどの高度化も考えられる
    # rm -f "$HISTORY_FILE"
    exit 0
}

# --- Script Entry Point ---
main "$@"
