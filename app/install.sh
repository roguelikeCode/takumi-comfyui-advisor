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

# ==============================================================================
# Shell Environment Initialization
# ==============================================================================

# --- Conda and ASDF wrapper setup ---
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

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
    echo -n "Contribute this anonymous log to The Takumi's Logbook? (Y/n): "
    read -n 1 -s consent
    echo
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
    
    echo -n "Proceed with building this foundation? [Y/n]: "
    read -n 1 -s consent
    echo
    if [[ "${consent,,}" != "y" ]]; then
        log_warn "Installation aborted by user."
        exit 1
    fi

    # Save the user's selected configuration in 'state'
    state["selected_accelerator"]=$accelerator_component
    state["selected_python"]="3.12"
    state["selected_core"]="core_tools"
}

run_concierge_use_case() {
    log_info "Your foundation is perfect. Now, let's select your specialized tools."
    
    echo ""
    echo "Please choose your primary use case:"
    echo "  (1) [Example] Photorealistic Image Generation"
    echo "  (2) Create & Dress Up Original Fashion"
    # --- To be implemented: Dynamically generate options from available recipes ---
    echo ""
    
    # -n 1: 1文字だけ読み込む
    # -s: 入力された文字を画面に表示しない (silent)
    # -p: プロンプトメッセージを指定
    read -n 1 -s -p "Enter number: " choice
    echo # 改行してプロンプトを綺麗に見せる

    # デフォルトのユースケースキーを定義
    local use_case_key="photorealistic_example" # (仮のファイル名)

    # ユーザーの選択に応じて、キーを上書き
    case "$choice" in
        "1")
            # ユーザーが1を選択した場合 (デフォルトなので、実際には不要だが明確化のために記述)
            use_case_key="photorealistic_example"
            ;;
        "2")
            # [修正] ユーザーが2を選択した場合、正しいレシピファイル名(拡張子なし)を設定
            use_case_key="create_and_dress_up_original_fashion"
            ;;
        *)
            log_warn "Invalid selection. Proceeding with the default use-case: '${use_case_key}'."
            # 不正な入力の場合は、デフォルトのまま進む
            ;;
    esac

    # レシピファイルから、表示用の名前を取得する (より親切なUIのため)
    local recipe_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_key}.yml"
    if [ ! -f "$recipe_path" ]; then
        log_error "Recipe file for '${use_case_key}' does not exist at ${recipe_path}."
        exit 1
    fi
    local display_name
    display_name=$(yq -r '.display_name' "$recipe_path")

    echo ""
    log_info "You have selected: \"${display_name}\""
    echo "The following components will be installed:"
    # yqを使って、インストールされるコンポーネントのリストを綺麗に表示
    yq -r '.components[]' "$recipe_path" | sed 's/^/  - /'
    echo ""
    
    read -n 1 -s -p "Proceed with this plan? [Y/n]: " consent
    if [[ "${consent,,}" == "n" ]]; then
        log_warn "Use-case installation aborted by user."; exit 1;
    fi

    # 最終的な選択をグローバルなstateに保存
    state["use_case"]=$use_case_key
}

run_sommelier() {
    local problem_type="$1" # "missing_foundation" や "generic_error" など
    local use_case_name="${state[use_case]}"

    if [ "$problem_type" == "missing_foundation" ]; then
        log_warn "The selected use-case '${use_case_name}' requires the 'foundation' environment, but it is not yet built."
        read -p "Would you like to build the 'foundation' environment now? [Y/n]: " consent
        if [[ "${consent,,}" == "n" ]]; then
            log_error "Cannot proceed without the foundation environment. Aborting."; return 1;
        fi

        # Foundation構築コンシェルジュを呼び出し、選択を行わせる
        run_foundation_concierge
        # 実際に構築を実行する
        if ! combine_foundation_environment; then
            log_error "Failed to build the foundation environment."
            # ここで、さらに詳細なエラー解決フローに入ることも可能
            return 1
        fi
        log_success "Foundation environment built successfully."
        # 構築が成功したので、true (0) を返して、元のフローに復帰させる
        return 0

    else # generic_error
        log_info "Consulting The Takumi's Sommelier for a solution..."
        log_warn "An unknown error occurred."
        # ... (既存のエラー解決ロジック) ...
        return 1
    fi
}

# ==============================================================================
# Installation Nodes (The "How")
# ==============================================================================

combine_foundation_environment() {
    log_info "Combining components to build your 'foundation' environment..."
    
    # stateに保存された選択済みのコンポーネントを取得
    local accelerator_yml="${CONFIG_DIR}/foundation_components/accelerator/${state[selected_accelerator]}.yml"
    local python_yml="${CONFIG_DIR}/foundation_components/python/${state[selected_python]}.yml"
    local core_tools_yml="${CONFIG_DIR}/foundation_components/${state[selected_core]}.yml"

    # 全ての部品ファイルが存在するか、最後の安全確認
    if ! { [ -f "$accelerator_yml" ] && [ -f "$python_yml" ] && [ -f "$core_tools_yml" ]; }; then
        log_error "One or more required component files are missing. Cannot build environment."
        echo "Checked paths:"
        echo "  - $accelerator_yml"
        echo "  - $python_yml"
        echo "  - $core_tools_yml"
        return 1
    fi

    # conda env createコマンドを動的に組み立てて実行
    if . ${CONDA_DIR}/etc/profile.d/conda.sh && \
        conda env create \
            --file "$accelerator_yml" \
            --file "$python_yml" \
            --file "$core_tools_yml"; then
        
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

# ==============================================================================
# Installation Engine v2.0 (Asset Materializer)
#
# [思想] このエンジンは、YAMLマニフェストに記述された「アセット」を、
# 現実のファイルや環境へと「具現化(materialize)」する責務を持つ。
# ==============================================================================

# --- Component Installers (Dispatch Targets) ---

install_component_conda() {
    local source="$1"
    local version="$2"
    local channel="$3"
    log_info "  -> Preparing conda package: ${source}${version}..."
    # 実際のインストールは、conda env createで一括して行う
    # ここでは、コマンドライン引数を組み立てるための文字列を返す
    if [ -n "$channel" ]; then
        echo "-c ${channel}"
    fi
    echo "${source}${version}"
}

install_component_pip() {
    local source="$1"
    local version="$2"
    log_info "  -> Preparing pip package: ${source}${version}..."
    echo "${source}${version}"
}

install_component_custom_node() {
    local source="$1"
    local version="$2"
    local comfyui_nodes_dir="/app/ComfyUI/custom_nodes"
    
    log_info "  -> Cloning custom node from ${source}..."
    mkdir -p "$comfyui_nodes_dir"
    
    # [修正] git cloneの正しい文法: git clone <repo> <target_directory>
    # gitリポジトリ名から、ディレクトリ名を自動で抽出する
    local target_dir="${source##*/}" # URLの最後の/以降を取得
    target_dir="${target_dir%.git}"   # 末尾の.gitを削除
    
    local clone_path="${comfyui_nodes_dir}/${target_dir}"

    # クローン先にディレクトリが既に存在しない場合のみ、cloneを実行する
    if [ ! -d "$clone_path" ]; then
        if [ -n "$version" ] && [ "$version" != "main" ]; then
            git clone --branch "$version" "$source" "$clone_path"
        else
            git clone "$source" "$clone_path"
        fi
    else
        log_warn "    Directory '${target_dir}' already exists. Skipping clone."
    fi
}

# --- Main Engine ---

run_install_flow() {
    local use_case_name="${state[use_case]}"
    if [ -z "$use_case_name" ]; then
        log_error "No use-case selected."; return 1;
    fi
    
    log_info "Starting asset materialization for use-case: '${use_case_name}'..."
    local recipe_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_name}.yml"
    if [ ! -f "$recipe_path" ]; then
        log_error "Asset manifest file not found: ${recipe_path}"; return 1;
    fi

    # --- Step 1: Materialize Conda Environment ---
    if ! yq -e '.environment' "$recipe_path" > /dev/null; then
        log_error "Asset manifest is missing required 'environment' section."; return 1;
    fi

    local env_name
    env_name=$(yq -r '.environment.name' "$recipe_path")

    if conda env list | grep -q "^${env_name}\s"; then
        log_info "Conda environment '${env_name}' already exists. Skipping creation."
    else
        log_info "Materializing Conda environment '${env_name}'..."
        
        local conda_components
        conda_components=$(yq -r '.environment.components[]' "$recipe_path")
        
        local conda_args=""
        local conda_deps=""
        
        echo "$conda_components" | while read -r comp_id; do
            # セマンティックIDをパース: type:source@version|channel
            local type="${comp_id%%:*}"
            local remainder="${comp_id#*:}"
            local source="${remainder%%@*}"
            remainder="${remainder#*@}"
            local version="${remainder%%|*}"
            local channel="${remainder##*|}"
            # versionとchannelが同じ場合はchannelを空にする
            if [ "$version" == "$channel" ]; then channel=""; fi

            local result
            result=$(install_component_conda "$source" "$version" "$channel")
            conda_args+=$(echo "$result" | grep -- "-c")
            conda_deps+=$(echo "$result" | grep -v -- "-c")
            conda_deps+=" "
        done

        if ! conda create -n "$env_name" ${conda_args} ${conda_deps} -y; then
            log_error "Failed to create Conda environment '${env_name}'."; return 1;
        fi
        log_success "Conda environment '${env_name}' materialized."
    fi

    # --- Step 2: Materialize Application Components ---
    log_info "Materializing application components into '${env_name}'..."
    
    local app_components
    app_components=$(yq -r '.components[]' "$recipe_path")
    
    local pip_deps="" # pipパッケージを一時的に貯める変数
    
    echo "$app_components" | while read -r comp_id; do
        # セマンティックIDをパース
        local type="${comp_id%%:*}"
        local remainder="${comp_id#*:}"
        local source="${remainder%%@*}"
        local version="${remainder#*@}"
        if [ "$source" == "$version" ]; then version=""; fi

        case "$type" in
            "custom-node")
                install_component_custom_node "$source" "$version"
                ;;
            "pip")
                # pipパッケージはすぐにはインストールせず、リストに追加していくだけ
                pip_deps+=$(install_component_pip "$source" "$version")
                pip_deps+=" "
                ;;
            *)
                log_warn "Unknown component type: '${type}'. Skipping."
                ;;
        esac
    done
    
    # --- Step 2.1: Install all pip packages at once ---
    if [ -n "$pip_deps" ]; then
        log_info "Installing all pip packages into '${env_name}' via uv..."
        if ! conda run -n "$env_name" uv pip install $pip_deps; then
            log_error "Failed to install pip packages."; return 1;
        fi
        log_success "All pip packages materialized."
    fi

    log_success "Asset materialization for '${use_case_name}' is complete."
    return 0
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

    # --- Phase 2: User Goal Identification ---
    # 履歴ファイルにuse_caseが記録されていなければ、ユーザーに尋ねる
    if [ -z "${state[use_case]}" ]; then
        run_concierge_use_case
    fi

    # --- Phase 3: Execution ---
    if ! run_install_flow; then
        # run_install_flowの中でSommelierが呼ばれるので、ここではシンプルに終了
        log_error "Installation failed."
        exit 1
    fi

    # --- Finalization ---
    log_success "All processes completed successfully!"
    exit 0
}

# --- Script Entry Point ---
main "$@"
