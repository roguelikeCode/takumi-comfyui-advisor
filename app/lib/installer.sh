#!/bin/bash

# [Why] To manage the core installation logic, including catalogs, packages, and environment setup.
# [What] Contains functions to fetch catalogs, install nodes/pip packages, and orchestrate the full install flow.

# --- Catalog Operations ---

# [Why] To retrieve the latest official custom node list from the internet.
# [What] Downloads 'custom-node-list.json' using wget.
# [Input] None (Uses global path constants)
fetch_external_catalogs() {
    log_info "Fetching latest external catalogs..."
    
    local manager_list_url="https://raw.githubusercontent.com/Comfy-Org/ComfyUI-Manager/main/custom-node-list.json"
    local external_catalog_path="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local external_catalog_dir
    external_catalog_dir=$(dirname "$external_catalog_path")

    mkdir -p "$external_catalog_dir"

    if wget --quiet -O "$external_catalog_path" "$manager_list_url"; then
        log_success "Successfully downloaded 'comfyui-manager/custom-node-list.json'."
        return 0
    else
        log_error "Failed to download 'comfyui-manager/custom-node-list.json'."
        log_warn "If you are offline, please ensure the file exists at: $external_catalog_path"
        return 1
    fi
}

# [Why] To combine the external list with Takumi's curated metadata.
# [What] Merges two JSON files into 'custom_nodes_merged.json' using jq.
# [Input] $1: entity_name (e.g., "custom_nodes")
build_merged_catalog() {
    local entity_name="$1"
    log_info "Building merged catalog for '${entity_name}'..."

    local merger_script="/app/scripts/merge_catalogs.py"
    local output_path="${CACHE_DIR}/catalogs/${entity_name}_merged.json"
    
    # Inputs
    local external_list="${EXTERNAL_DIR}/comfyui-manager/custom-node-list.json"
    local core_meta="${CONFIG_DIR}/takumi_meta/core/entities/${entity_name}_meta.json"
    local ent_meta="${CONFIG_DIR}/takumi_meta/enterprise/entities/${entity_name}_meta.json"

    # Leaving it all to the Python script
    python3 "$merger_script" "$output_path" "$external_list" "$core_meta" "$ent_meta"
    
    if [ $? -eq 0 ]; then
        log_success "Catalog merged."
    else
        log_error "Catalog merge failed."
        return 1
    fi
}

# --- Component Installers ---

# [Why] To prevent 'IncompleteRead' errors on unstable connections.
# [What] Temporarily boosts Conda's timeout and retry settings.
enhance_conda_network() {
    log_info "  -> 🛡️  Activating network resilience patch..."
    conda config --set remote_read_timeout_secs 600.0
    conda config --set remote_connect_timeout_secs 60.0
    conda config --set remote_max_retries 10
}

# [Why] To restore default Conda settings after operations.
# [What] Removes the temporary overrides.
restore_conda_network() {
    log_info "  -> 🛡️  Restoring default network settings..."
    conda config --remove-key remote_read_timeout_secs > /dev/null 2>&1 || true
    conda config --remove-key remote_connect_timeout_secs > /dev/null 2>&1 || true
    conda config --remove-key remote_max_retries > /dev/null 2>&1 || true
}

# [Why] To clone repositories safely without overwriting mounted data.
# [What] Checks for existing .git or non-empty directories (mounts) before cloning.
# [Input] $1: source_url, $2: target_path, $3: branch (optional)
git_clone_safely() {
    local source="$1"
    local path="$2"
    local branch="$3"

    # Case 1: Valid Repo exists (Idempotency)
    if [ -d "$path/.git" ]; then
        log_info "  -> Valid repository exists at ${path}. Skipping clone."
        return 0
    fi

    # Case 2: Directory exists and is NOT empty (Likely a Volume Mount)
    # [Note] `ls -A` returns contents including hidden files. If content exists, we protect it.
    if [ -d "$path" ] && [ "$(ls -A "$path")" ]; then
        log_warn "  -> Target '${path}' is not empty (likely mounted data)."
        log_warn "     Skipping clone to protect your data."
        return 0
    fi

    # Case 3: Pristine or Empty Directory (Safe to Clone)
    log_info "  -> Cloning into pristine directory: ${path}..."
    mkdir -p "$path"
    
    local git_args=("--recursive")
    if [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "master" ] && [ "$branch" != "null" ]; then
        git_args+=("--branch" "$branch")
    fi
    
    git clone "${git_args[@]}" "$source" "$path"
}

# Bandit (SAST)
# [Why] To detect security issues in custom nodes using AST analysis.
# [Input] $1: target_directory
run_bandit_scan() {
    local target_dir="$1"
    if [ ! -d "$target_dir" ]; then return 0; fi

    log_info "  -> 🛡️  Auditing code with Bandit (Configured)..."

    # Install bandit if missing
    if ! command -v bandit &> /dev/null; then
        # If you are in a virtual environment, use 'pip install'
        pip install bandit -q 2>/dev/null || true
    fi

    # Config file path (path within container)
    local config_file="/app/.bandit"
    local cmd_opts="-r $target_dir -f txt"

    # Use the configuration file if it exists, otherwise use the default (High/High)
    if [ -f "$config_file" ]; then
        cmd_opts="$cmd_opts -c $config_file"
    else
        cmd_opts="$cmd_opts -lll" # High Severity Only
    fi

    # Run Scan
    # Consider using '|| true' so that the script does not stop even if a failure (vulnerability) occurs.
    # Here, we will issue a warning and proceed if a vulnerability is detected.
    if bandit $cmd_opts > /tmp/bandit_report.txt 2>&1; then
        log_success "  -> 🛡️  Security check passed."
    else
        log_warn "  ⚠️  Security risks detected by Bandit!"
        log_warn "     Review details in logs."
        # Display only important lines (false positive prevention)
        grep -E "Test ID:|Severity:|Location:" /tmp/bandit_report.txt | head -n 10 | sed 's/^/     /'
    fi
}

# [Why] To install a specific Custom Node from the catalog.
# [What] Resolves URL from catalog ID and git clones it.
# [Input] $1: id, $2: version
install_component_custom_node() {
    local source="$1"  # ID or URL
    local version="$2"
    local comfyui_nodes_dir="${COMFYUI_CUSTOM_NODES_DIR}"
    
    local url=""
    
    # Check if source is a URL (starts with http)
    if [[ "$source" == http* ]]; then
        url="$source"
    else
        # Fallback to catalog lookup (ID based)
        local meta_file="${CACHE_DIR}/catalogs/custom_nodes_merged.json"
        if [ -f "$meta_file" ]; then
            url=$(jq -r --arg id "$source" '.[$id].url // empty' "$meta_file")
        fi
    fi

    if [ -z "$url" ]; then
        log_error "  -> Custom Node source '${source}' not found (Invalid ID or URL)."
        return 1
    fi

    # Extract directory name from URL (e.g., ComfyUI_MagicClothing)
    local repo_name=$(basename "$url" .git)
    local clone_path="${comfyui_nodes_dir}/${repo_name}"

    log_info "  -> Cloning custom node from ${url}..."
    
    if [ ! -d "$clone_path" ]; then
        git clone "$url" "$clone_path"
        if [ -n "$version" ] && [ "$version" != "main" ] && [ "$version" != "null" ]; then
            (cd "$clone_path" && git checkout "$version")
        fi
    else
        log_info "    Directory '${repo_name}' already exists. Updating..."
        (cd "$clone_path" && git pull)
    fi

    # [Security] Run scanner after install/update
    run_bandit_scan "$clone_path"
}

# [Why] To install extra pip packages defined in a separate JSON recipe.
# [What] Parses JSON and runs 'pip install' in the current conda environment.
# [Input] $1: recipe_path
install_pip_from_recipe() {
    local recipe_path="$1"
    
    # This is normal for OSS version (dashboard recipe is missing)
    if [ ! -f "$recipe_path" ]; then
        if [[ "$recipe_path" == *"dashboard"* ]]; then
            log_info "Skipping Enterprise components (Normal for OSS Edition)."
        else
            log_warn "Recipe not found: $recipe_path"
        fi
        return 0
    fi

    log_info "Processing extra recipe: $recipe_path"

    local pip_deps=()
    while IFS=$'\t' read -r type source version; do
        if [ "$type" == "pip" ]; then
            if [ "$version" != "null" ] && [ -n "$version" ]; then
                pip_deps+=("${source}${version}")
            else
                pip_deps+=("${source}")
            fi
        fi
    done < <(jq -r '.components[] | select(.type=="pip") | [.type, .source, .version] | @tsv' "$recipe_path")

    if [ ${#pip_deps[@]} -gt 0 ]; then
        log_info "  -> Installing extra pip packages..."
        
        if ! UV_LINK_MODE=copy conda run \
            -n "${state[use_case_env]}" \
            --no-capture-output \
            uv pip install "${pip_deps[@]}"; then
            
            log_error "Failed to install packages from $recipe_path"
            return 1
        fi
    fi
}

# [Why] To ensure the AI model is ready for the Chat UI.
# [What] Starts Ollama server and pulls the required model if missing.
# [Note] gemma2:2b provides the best balance of speed and instruction following
setup_ollama_model() {
    local model_name="gemma2:2b"
    log_info "Setting up AI Model (${model_name})..."

    if ! pgrep -x "ollama" > /dev/null; then
        ollama serve > /dev/null 2>&1 &
        sleep 5
    fi

    if ollama list | grep -q "${model_name}"; then
        log_info "  -> Model '${model_name}' is already installed."
    else
        log_info "  -> Pulling '${model_name}'..."
        if ! ollama pull "${model_name}"; then
            log_warn "Failed to pull model '${model_name}'. Run 'ollama pull ${model_name}' manually."
        else
            log_success "Model '${model_name}' installed."
        fi
    fi
}

# --- Main Flow ---

# [Why] To orchestrate the entire installation process based on the selected recipe.
# [What] Creates Conda env, installs Git/Pip components, runs Asset Manager, and sets up Brain.
# [Input] Global: $state[use_case]
run_install_flow() {
    local use_case_name="${state[use_case]}"
    if [ -z "$use_case_name" ]; then
        log_error "No use-case selected."; return 1;
    fi
    
    log_info "Starting asset materialization for use-case: '${use_case_name}'..."

    # 0. Install System Foundation (ComfyUI)
    log_info "Materializing system foundation (ComfyUI)..."
    if [ ! -d "${COMFYUI_ROOT_DIR}/.git" ]; then
        log_info "  -> Cloning ComfyUI repository to ${COMFYUI_ROOT_DIR}..."
        git clone "https://github.com/Comfy-Org/ComfyUI.git" "${COMFYUI_ROOT_DIR}"
    else
        log_info "  -> ComfyUI repository already exists. Skipping clone."
    fi
    
    # Use a function in 'utils.sh' to search for 'Core' or 'Ent'
    local raw_recipe_path
    raw_recipe_path=$(find_use_case_recipe_path "$use_case_name")

    if [ -z "$raw_recipe_path" ]; then
        log_error "Recipe not found for use-case: ${use_case_name}"
        return 1
    fi

    # Detect Hardware & Select Environment
    local env_id=$(detect_optimal_environment)
    log_info "  -> 🖥️  Hardware Profile: $env_id"

    # Recipe Integration with Python
    log_info "🧬 Fusing recipes with environment..."
    local merged_recipe_path="/tmp/merged_recipe.json"
    
    if ! python3 /app/scripts/merge_recipes.py "$raw_recipe_path" "$env_id" > "$merged_recipe_path"; then
        log_error "Failed to merge recipes."
        return 1
    fi
    
    # Use merged JSON from now on
    local use_case_path="$merged_recipe_path"

    # 1. Conda Environment
    local env_name
    env_name=$(jq -r '.environment.name' "$use_case_path")
    state["use_case_env"]=$env_name

    if conda env list | grep -q "^${env_name}\s"; then
        log_info "Conda environment '${env_name}' already exists. Skipping creation."
    else
        log_info "Materializing Conda environment '${env_name}'..."
        
        local conda_pkgs=()
        local channels=()

        # [1] Load Global Channels (from YAML)
        while IFS= read -r ch; do
            if [ -n "$ch" ] && [ "$ch" != "null" ]; then
                channels+=("-c" "$ch")
            fi
        done < <(jq -r '.environment.channels[]? // empty' "$use_case_path")

        # [2] Load Components
        while IFS=$'\t' read -r type source version channel; do
            if [ "$version" == "null" ]; then version=""; fi
            if [ "$channel" == "null" ]; then channel=""; fi
            
            # Optional component channel
            if [ -n "$channel" ]; then 
                channels+=("-c" "$channel")
            fi
            
            # Version constraint handling
            # Regex stored in variable to avoid Bash syntax errors with < >
            local constraint_regex='^[=<>!]'
            
            if [ -n "$version" ]; then
                if [[ "$version" =~ $constraint_regex ]]; then
                    conda_pkgs+=("${source}${version}")
                elif [[ "$version" =~ ^[0-9] ]]; then
                    conda_pkgs+=("${source}=${version}")
                else
                    conda_pkgs+=("${source}${version}")
                fi
            else
                conda_pkgs+=("${source}")
            fi
        done < <(jq -r '.environment.components[] | [.type, .source, .version, .channel] | @tsv' "$use_case_path")

        # [3] Create Environment
        enhance_conda_network
        
        if ! conda create -n "$env_name" "${channels[@]}" "${conda_pkgs[@]}" -y; then
             restore_conda_network
             consult_ai_on_complex_failure \
                "Failed to create Conda environment '${env_name}'." \
                "Packages: ${conda_pkgs[*]}"
            return 1
        fi

        restore_conda_network
        log_success "Conda environment '${env_name}' materialized."
    fi

    # 2. Application Components
    log_info "Materializing application components into '${env_name}'..."
    local pip_deps=()

    # --- Component Loop (Git/Pip) ---
    while IFS=$'\t' read -r type source version path; do
        if [ "$version" == "null" ]; then version=""; fi
        if [ "$path" == "null" ]; then path=""; fi

        log_info "Processing: [${type}] ${source}"

        case "$type" in
            "git-clone")
                # Override path for ComfyUI root if necessary
                if [[ "$source" == *"Comfy-Org/ComfyUI.git"* ]]; then
                    path="${COMFYUI_ROOT_DIR}"
                fi

                if [ -z "$path" ]; then 
                    log_error "Path required for git-clone: ${source}"
                    continue
                fi
                
                # Call the safe clone function
                git_clone_safely "$source" "$path" "$version"
                ;;
                
            "custom-node")
                install_component_custom_node "$source" "$version"
                ;;
            "pip")
                if [ -n "$version" ]; then pip_deps+=("${source}${version}"); else pip_deps+=("${source}"); fi
                ;;
            *)
                log_warn "Unknown component type: '${type}'"
                ;;
        esac
    done < <(jq -r '.components[] | [.type, .source, .version, .path // ""] | @tsv' "$use_case_path")

    # 3. Pip Installation
    if [ ${#pip_deps[@]} -gt 0 ]; then
        log_info "Installing pip packages into '${env_name}' via uv..."
        
        # Explicitly activate environment in a subshell to ensure 'uv' installs to the correct target.
        # This avoids variable binding conflicts (set +u/-u) between our strict shell script and Conda's internal scripts.
        if ! (
            source /opt/conda/etc/profile.d/conda.sh
            set +u
            conda activate "$env_name"
            set -u
            export UV_LINK_MODE=copy
            uv pip install "${pip_deps[@]}"
        ); then
             consult_ai_on_complex_failure \
                "Failed to install pip packages via uv." \
                "Target Env: $env_name, Packages: ${pip_deps[*]}"
            return 1
        fi
        log_success "All pip packages materialized."
    fi

    # 4. Dependency Resolver
    # [Why] To ensure environment stability by verifying installed nodes
    # [What] Scans for requirements.txt and attempts to resolve missing packages locally
    local resolver_script="/app/scripts/resolve_dependencies.py"
    
    if [ -f "$resolver_script" ]; then
        log_info "🛡️  Verifying dependencies..."
        
        # Execute Resolver inside the environment
        (
            source /opt/conda/etc/profile.d/conda.sh
            set +u
            conda activate "${state[use_case_env]}"
            set -u
            
            # Use python instead of python3
            # (Because python takes precedence as shim in a Conda environment)
            python "$resolver_script"
        ) || log_warn "Dependency check finished with warnings. See logs/resolver_report.json."
        
        # Note: The '||' above catches the exit code if python script fails (returns non-zero),
        # allowing the installer to proceed instead of stopping immediately.
        # Original logic:
        # if ! python3 "$resolver_script"; then
        #    log_warn ...
        # else
        #    log_success ...
        # fi
        # The subshell approach simplifies this flow.
    fi

    # 5. Asset Manager
    # [Why] Determine the correct asset recipe based on the selected use case

    local asset_recipe_file=""
    asset_recipe_file=$(jq -r '.asset_recipe // empty' "$use_case_path")
    
    if [ -n "$asset_recipe_file" ]; then
        log_info "Searching for Asset Recipe: ${asset_recipe_file}..."
        
        # [Fix] Namespace Search Strategy (Enterprise -> Core)
        local asset_recipe_full_path=""
        local base_meta_dir="${CONFIG_DIR}/takumi_meta"
        
        # 1. Check Enterprise
        local ent_candidate="${base_meta_dir}/enterprise/recipes/${asset_recipe_file}"
        # 2. Check Core
        local core_candidate="${base_meta_dir}/core/recipes/${asset_recipe_file}"

        if [ -f "$ent_candidate" ]; then
            asset_recipe_full_path="$ent_candidate"
            log_info "  -> Found in [Enterprise]"
        elif [ -f "$core_candidate" ]; then
            asset_recipe_full_path="$core_candidate"
            log_info "  -> Found in [Core]"
        else
            log_error "Asset Recipe defined but not found in directories."
            log_warn "  Checked: $ent_candidate"
            log_warn "  Checked: $core_candidate"
            # Since it is not possible to continue, should I issue an error or skip? This time, I should issue an error instead of skipping, but I will continue for now.
        fi
        
        if [ -n "$asset_recipe_full_path" ]; then
            log_info "Launching Takumi Asset Manager..."
            
            local manager_script="${APP_ROOT}/scripts/asset_manager.py"
            
            if [ -f "$manager_script" ]; then
                (
                    source /opt/conda/etc/profile.d/conda.sh
                    set +u
                    conda activate "$env_name"
                    set -u
                    export COMFYUI_ROOT_DIR="${COMFYUI_ROOT_DIR}"
                    export HF_TOKEN="${HF_TOKEN}" # Pass the token too
                    
                    # Execute Asset Manager
                    python -u "$manager_script" "$asset_recipe_full_path"
                )
                if [ $? -ne 0 ]; then
                    log_error "Asset Manager encountered an issue."
                    return 1
                fi
            else
                log_warn "Asset Manager script not found."
            fi
        fi
    else
        log_info "No asset recipe defined for this use case. Skipping Asset Manager."
    fi

    # 6. Brain
    setup_ollama_model() {
        local model_name="gemma2:2b"
        log_info "Setting up AI Model (${model_name})..."

        # 1. Start the server if it is not running
        if ! pgrep -x "ollama" > /dev/null; then
            log_info "  -> Starting Ollama server..."
            # Prevent buffer congestion by discarding logs & background execution
            ollama serve > /dev/null 2>&1 &
        fi

        # 2. Startup wait loop (Heartbeat Check)
        # Instead of simply sleeping, it actually waits up to 20 seconds until it can connect.
        log_info "  -> Waiting for Ollama API to be ready..."
        local max_retries=20
        local count=0
        
        # Check if you can connect to 127.0.0.1:11434
        while ! curl -s http://127.0.0.1:11434 > /dev/null; do
            sleep 2
            ((count++))
            if [ "$count" -ge "$max_retries" ]; then
                log_warn "Ollama server failed to start within timeout."
                # Failure does not stop the entire installation (because it is a non-essential component)
                return 0 
            fi
            echo -n "."
        done
        echo "" # Line breaks

        # 3. Checking and Pulling the Model
        if ollama list | grep -q "${model_name}"; then
            log_info "  -> Model '${model_name}' is already installed."
        else
            log_info "  -> Pulling '${model_name}'..."
            if ! ollama pull "${model_name}"; then
                log_warn "Failed to pull model '${model_name}'. Run 'ollama pull ${model_name}' manually."
            else
                log_success "Model '${model_name}' installed."
            fi
        fi
    }

    # Save the active environment name for run.sh
    echo "${env_name}" > "${ACTIVE_ENV_FILE}"

    log_success "Asset materialization for '${use_case_name}' is complete."
    return 0
}

# [Why] To execute external extension scripts overlaid by enterprise editions.
# [What] Scans the hook directory and sources any .sh files found.
# [Input] $1: hook_name (e.g., "post_install", "on_boot")
run_extension_hooks() {
    local hook_name="$1"
    # enterprise version mounted directory
    local hook_dir="/app/extensions/hooks/${hook_name}"

    if [ -d "$hook_dir" ]; then
        log_info "🔌 Running extensions for: ${hook_name}"
        
        # Run in alphabetical order (01_init.sh, 02_setup.sh ...)
        for script in $(find "$hook_dir" -maxdepth 1 -name "*.sh" | sort); do
            if [ -f "$script" ]; then
                log_info "  -> Executing extension: $(basename "$script")"
                # By executing source, the current context (variables and functions) is shared.
                source "$script"
            fi
        done
    fi
}