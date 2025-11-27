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
    if [ "$DEV_MODE" = "true" ]; then
        # ... (既存のローカル保存ロジック) ...
        return
    fi

    # --- Production Mode ---
    echo -n "Contribute this anonymous log to The Takumi's Logbook? (Y/n): "
    read -n 1 -s consent
    echo
    if [[ "${consent,,}" != "n" ]]; then
        log_info "Thank you. Submitting log to the collective intelligence..."

        # [修正] あなたのAPI GatewayのURLに書き換えてください
        local api_url="https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"

        # curlでPOST送信
        # -s: 静かに実行 (進捗バーを出さない)
        # -o /dev/null: 結果を画面に出さない
        # -w "%{http_code}": HTTPステータスコードだけを表示
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$log_content" \
            "$api_url")

        if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 201 ]; then
            log_success "Log submitted successfully."
        else
            log_warn "Failed to submit log (HTTP $status_code). Saved locally instead."
            # 失敗したらローカルに保存するなどのフォールバックがあると親切
        fi
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

    local jq_command="jq"
    local merged_catalog_dir="${CACHE_DIR}/catalogs"
    
    local external_catalog="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local takumi_meta_catalog="${CONFIG_DIR}/takumi_meta/entities/${entity_name}_meta.json"
    local merged_catalog_path="${merged_catalog_dir}/${entity_name}_merged.json"

    if [ ! -f "$external_catalog" ]; then
        log_error "External catalog not found: $external_catalog"; return 1;
    fi
    if [ ! -f "$takumi_meta_catalog" ]; then
        log_error "Takumi meta catalog not found: $takumi_meta_catalog"; return 1;
    fi

    mkdir -p "$merged_catalog_dir"

    # [修正] 型チェックを追加した、極めて堅牢なマージロジック
    # 外部リストの中に想定外のデータ(配列など)が混じっていても、無視して処理を続行する
    "$jq_command" -s '
        # 1. 外部リストの取得: .custom_nodesキーの中身、なければルートそのものを使う
        ( (.[0].custom_nodes // .[0]) | 
          reduce .[] as $item ({}; 
            # ガード節: オブジェクトかつURL(reference)持ちのみインデックス化
            if ($item | type) == "object" and ($item | has("reference")) then
                . + { ($item.reference): $item }
            else
                . 
            end
        )) as $index |

        # 2. Takumiメタデータ(.[1])をマージ
        .[1] | map_values(
            . + ($index[.url] // {}) 
        )
    ' \
    "$external_catalog" \
    "$takumi_meta_catalog" \
    > "$merged_catalog_path"
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
# The Takumi's Concierge
# ==============================================================================

run_concierge_use_case() {
    log_info "Your foundation is perfect. Now, let's select your specialized tools."
    
    echo ""
    echo "Please choose your primary use case:"
    echo "  (1) [Defaults] (Basic setup)"
    echo "  (2) Create & Dress Up Original Fashion (MagicClothing)"
    echo ""
    
    read -n 1 -s -p "Enter number: " choice
    echo ""

    local use_case_filename="defaults"

    case "$choice" in
        "1")
            use_case_filename="defaults"
            ;;
        "2")
            use_case_filename="create_and_dress_up_original_fashion"
            ;;
        *)
            log_warn "Invalid selection. Proceeding with the default use-case: '${use_case_filename}'"
            ;;
    esac

    # --- UI ---
    local use_case_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_filename}.json"
    
    if [ ! -f "$use_case_path" ]; then
        log_error "Asset manifest file for '${use_case_filename}' does not exist at ${use_case_path}."
        exit 1
    fi

    # [修正] jqでJSONをパース
    local display_name
    display_name=$(jq -r '.display_name' "$use_case_path")

    echo ""
    log_info "You have selected: \"${display_name}\""
    echo "The following components will be installed:"
    
    # [修正] jqの複雑な構文をやめ、実績のあるTSV方式で読み込み、シェルで整形する
    # これにより "lexer: invalid input text" エラーを回避し、警告も抑制(-o tsv)する
    jq -r '.components[] | [.type, .source, .version] | @tsv' "$use_case_path" | \
    while IFS=$'\t' read -r type source version; do
        # null または空文字のチェック
        if [ "$version" == "null" ] || [ -z "$version" ]; then
            echo "  - [${type}] ${source}"
        else
            echo "  - [${type}] ${source} (${version})"
        fi
    done
    
    echo ""
    read -n 1 -s -p "Proceed with this plan? [Y/n]: " consent
    echo ""

    if [[ "${consent,,}" == "n" ]]; then
        log_warn "Use-case installation aborted by user."
        exit 1
    fi

    state["use_case"]=$use_case_filename
}

# ==============================================================================
# Installation Engine v4.0 (Asset Materializer - JSON Native)
#
# [思想] JSON形式のアセット・マニフェストを読み込み、
# 構造化されたデータを直接処理することで、文字列パースの脆さを排除する。
# ==============================================================================

# --- Component Installers ---

install_component_custom_node() {
    local id="$1"
    local version="$2"
    local comfyui_nodes_dir="/app/ComfyUI/custom_nodes"
    
    # [修正] キャッシュされたカタログファイル (JSON)
    local meta_file="${CACHE_DIR}/catalogs/custom_nodes_merged.json"
    
    # [修正] jqを使ってURLを確実に抽出する
    local url
    if [ -f "$meta_file" ]; then
        url=$(jq -r --arg id "$id" '.[$id].url // empty' "$meta_file")
    else
        log_error "Catalog file not found: $meta_file"
        return 1
    fi

    if [ -z "$url" ]; then
        log_error "  -> Custom Node ID '${id}' not found in catalog. Skipping."
        # デバッグ用: カタログにキーがあるか確認
        # jq -r keys "$meta_file" | grep "$id"
        return 1
    fi

    log_info "  -> Cloning custom node '${id}' from ${url}..."
    mkdir -p "$comfyui_nodes_dir"
    
    local target_dir="${url##*/}"
    target_dir="${target_dir%.git}"
    local clone_path="${comfyui_nodes_dir}/${target_dir}"

    if [ ! -d "$clone_path" ]; then
        if [ -n "$version" ] && [ "$version" != "main" ] && [ "$version" != "null" ]; then
            git clone --branch "$version" "$url" "$clone_path"
        else
            git clone "$url" "$clone_path"
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
    
    # .json を読み込む
    local use_case_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_name}.json"
    
    if [ ! -f "$use_case_path" ]; then
        log_error "Asset manifest file not found: ${use_case_path}"; return 1;
    fi

    # --- Step 1: Materialize Conda Environment ---
    
    # [修正] JSONをパースして、conda createコマンドを動的に組み立てる
    # これにより、マニフェストの 'components' キーを condaの引数として正しく変換できる
    
    local env_name
    env_name=$(jq -r '.environment.name' "$use_case_path")

    if conda env list | grep -q "^${env_name}\s"; then
        log_info "Conda environment '${env_name}' already exists. Skipping creation."
    else
        log_info "Materializing Conda environment '${env_name}'..."
        
        local conda_pkgs=()
        local channels=()

        # jqでTSVに変換して読み込む
        while IFS=$'\t' read -r type source version channel; do
            # nullチェック
            if [ "$version" == "null" ]; then version=""; fi
            if [ "$channel" == "null" ]; then channel=""; fi

            # チャンネル指定がある場合
            if [ -n "$channel" ]; then
                # 配列にまだ含まれていなければ追加するロジックが望ましいが、
                # condaは重複を許容するのでそのまま追加
                channels+=("-c" "$channel")
            fi
            
            # パッケージ指定 (python=3.10 の形式にする)
            if [ -n "$version" ]; then
                # バージョン指定が = で始まっていなければ = を付けるなどの正規化も可能だが
                # ここではマニフェストが正しいと仮定する (例: python, 3.10 -> python=3.10)
                # ただし、マニフェストで "version": "3.10" となっているので "=" を補う
                if [[ "$version" != =* ]] && [[ "$version" =~ ^[0-9] ]]; then
                    conda_pkgs+=("${source}=${version}")
                else
                    conda_pkgs+=("${source}${version}")
                fi
            else
                conda_pkgs+=("${source}")
            fi
        done < <(jq -r '.environment.components[] | [.type, .source, .version, .channel] | @tsv' "$use_case_path")

        # コマンド実行
        # "${channels[@]}" "${conda_pkgs[@]}" で配列を展開
        if ! conda create -n "$env_name" "${channels[@]}" "${conda_pkgs[@]}" -y; then
            log_error "Failed to create Conda environment '${env_name}'."; return 1;
        fi
        
        log_success "Conda environment '${env_name}' materialized."
    fi

    # --- Step 2: Materialize Application Components ---
    log_info "Materializing application components into '${env_name}'..."
    
    local pip_deps=()

    # [修正1] jqコマンド: .path も抽出するように追加 (.path // "" はnullなら空文字にする意)
    # [修正2] readコマンド: path 変数を受け取るように追加
    while IFS=$'\t' read -r type source version path; do
        if [ "$version" == "null" ]; then version=""; fi
        if [ "$path" == "null" ]; then path=""; fi

        log_info "Processing: [${type}] ${source}"

        case "$type" in
            "git-clone")
                # [新設] 汎用的なGit Clone処理
                if [ -z "$path" ]; then
                    log_error "Path is required for git-clone type: ${source}"; continue;
                fi
                log_info "  -> Cloning repository to ${path}..."
                
                if [ ! -d "$path" ]; then
                    if [ -n "$version" ] && [ "$version" != "main" ] && [ "$version" != "master" ]; then
                         git clone --branch "$version" "$source" "$path"
                    else
                         git clone "$source" "$path"
                    fi
                else
                    log_warn "    Directory ${path} already exists. Skipping."
                fi
                ;;

            "custom-node")
                install_component_custom_node "$source" "$version"
                ;;

            "pip")
                if [ -n "$version" ]; then
                    pip_deps+=("${source}${version}")
                else
                    pip_deps+=("${source}")
                fi
                ;;
            *)
                log_warn "Unknown component type: '${type}'"
                ;;
        esac

    done < <(jq -r '.components[] | [.type, .source, .version, .path // ""] | @tsv' "$use_case_path")

    # --- Step 2.1: Install pip packages ---
    if [ ${#pip_deps[@]} -gt 0 ]; then
        log_info "Installing pip packages into '${env_name}' via uv..."
        # プログレスバーが見えるように --no-capture-output を推奨
        if ! conda run -n "$env_name" --no-capture-output uv pip install "${pip_deps[@]}"; then
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
    log_info "Takumi Installer Engine v4.0 starting..."

    # --- Phase 1: Preparation ---
    if ! fetch_external_catalogs; then
        log_warn "Could not fetch external catalogs. Proceeding with local files if available."
    fi

    if ! build_merged_catalog "custom_nodes"; then
        log_error "Failed to prepare essential catalogs. Installation cannot proceed."
        exit 1
    fi

    # --- Phase 2: User Goal Identification ---
    # 以前の履歴読み込みロジックは、アーキテクチャ変更により一旦削除
    # 常にコンシェルジュを起動する（将来的に再開機能を実装）
    if [ -z "${state[use_case]}" ]; then
        run_concierge_use_case
    fi

    # --- Phase 3: Execution ---
    if ! run_install_flow; then
        log_error "Installation failed."
        exit 1
    fi

    # --- Phase 4: Log Submission (ここを追加！) ---
    # 送信するデータをJSON形式で作成
    local log_payload
    log_payload=$(cat <<EOF
{
  "status": "success",
  "use_case": "${state[use_case]}",
  "accelerator": "${state[selected_accelerator]:-unknown}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    # 作成したデータを渡して送信関数を呼び出す
    submit_log_to_takumi "$log_payload"

    # --- Finalization ---
    log_success "All processes completed successfully!"
    exit 0
}

# --- Script Entry Point ---
# [修正] 直接実行された場合のみ main を呼び出す。
# 他のスクリプトから source された場合は、関数定義だけを読み込んで何もしない。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
