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

    # Merge logic: External list + Takumi metadata
    "$jq_command" -s '
        ( (.[0].custom_nodes // .[0]) | 
          reduce .[] as $item ({}; 
            if ($item | type) == "object" and ($item | has("reference")) then
                . + { ($item.reference): $item }
            else
                . 
            end
        )) as $index |
        .[1] | map_values(
            . + ($index[.url] // {}) 
        )
    ' "$external_catalog" "$takumi_meta_catalog" > "$merged_catalog_path"
}

# --- Component Installers ---

# [Why] To install a specific Custom Node from the catalog.
# [What] Resolves URL from catalog ID and git clones it.
# [Input] $1: id, $2: version
install_component_custom_node() {
    local source="$1"  # ID or URL
    local version="$2"
    local comfyui_nodes_dir="/app/ComfyUI/custom_nodes"
    
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
    
    local use_case_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_name}.json"
    
    if [ ! -f "$use_case_path" ]; then
        log_error "Asset manifest file not found: ${use_case_path}"; return 1;
    fi

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

        while IFS=$'\t' read -r type source version channel; do
            if [ "$version" == "null" ]; then version=""; fi
            if [ "$channel" == "null" ]; then channel=""; fi
            if [ -n "$channel" ]; then channels+=("-c" "$channel"); fi
            
            if [ -n "$version" ]; then
                if [[ "$version" != =* ]] && [[ "$version" =~ ^[0-9] ]]; then
                    conda_pkgs+=("${source}=${version}")
                else
                    conda_pkgs+=("${source}${version}")
                fi
            else
                conda_pkgs+=("${source}")
            fi
        done < <(jq -r '.environment.components[] | [.type, .source, .version, .channel] | @tsv' "$use_case_path")

        if ! conda create -n "$env_name" "${channels[@]}" "${conda_pkgs[@]}" -y; then
             consult_ai_on_complex_failure \
                "Failed to create Conda environment '${env_name}'." \
                "Packages: ${conda_pkgs[*]}"
            return 1
        fi
        log_success "Conda environment '${env_name}' materialized."
    fi

    # 2. Application Components
    log_info "Materializing application components into '${env_name}'..."
    local pip_deps=()

    while IFS=$'\t' read -r type source version path; do
        if [ "$version" == "null" ]; then version=""; fi
        if [ "$path" == "null" ]; then path=""; fi

        log_info "Processing: [${type}] ${source}"

        case "$type" in
            "git-clone")
                if [ -z "$path" ]; then log_error "Path required for git-clone: ${source}"; continue; fi
                
                # Check if valid repo exists (.git check)
                # If the directory does not exist or .git does not exist, it will be cloned.
                if [ ! -d "$path/.git" ]; then
                    log_info "  -> Cloning repo to ${path}..."
                    
                    # Cleaning up mounted empty directories
                    if [ -d "$path" ]; then
                        log_info "    (Cleaning existing directory to ensure clean clone...)"
                        find "$path" -mindepth 1 -delete 2>/dev/null || true
                    fi

                    # Building Command Arguments (Builder Pattern)
                    local git_args=("--recursive")
                    
                    # Add branch argument only if version is specified
                    if [ -n "$version" ] && [ "$version" != "main" ] && [ "$version" != "master" ]; then
                        git_args+=("--branch" "$version")
                    fi

                    # Execution
                    # "${git_args[@]}" is expanded and passed as options
                    git clone "${git_args[@]}" "$source" "$path"
                else
                    log_info "    Repository valid at ${path}. Skipping."
                fi
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

    # 4. Asset Manager
    # [Why] Determine the correct asset recipe based on the selected use case
    local asset_recipe=""
    
    if [[ "$use_case_name" == *"fashion"* ]] || [[ "$use_case_name" == *"magic"* ]]; then
        asset_recipe="${CONFIG_DIR}/takumi_meta/recipes/assets/magic_clothing.json"
    elif [[ "$use_case_name" == *"video"* ]] || [[ "$use_case_name" == *"animation"* ]]; then
        asset_recipe="${CONFIG_DIR}/takumi_meta/recipes/assets/animate_diff.json"
    fi

    if [ -n "$asset_recipe" ]; then
        log_info "Launching Takumi Asset Manager with recipe: $(basename "$asset_recipe")..."
        local manager_script="${APP_ROOT}/scripts/asset_manager.py"
        
        if [ -f "$manager_script" ] && [ -f "$asset_recipe" ]; then
            # To ensure progress bars are visible and environment is correctly activated
            # Run in subshell with unbuffered output (-u)
            (
                source /opt/conda/etc/profile.d/conda.sh
                set +u
                conda activate "$env_name"
                set -u
                # Pass the recipe path as an argument
                python -u "$manager_script" "$asset_recipe"
            )
            
            if [ $? -ne 0 ]; then
                log_error "Asset Manager encountered an issue (check logs)."
                return 1
            fi
        else
            log_warn "Asset Manager script or Recipe not found."
        fi
    fi

    # 5. Brain
    setup_ollama_model

    # Save the active environment name for run.sh
    echo "${env_name}" > "${ACTIVE_ENV_FILE}"

    log_success "Asset materialization for '${use_case_name}' is complete."
    return 0
}

# [Why] To execute external extension scripts overlaid by commercial editions.
# [What] Scans the hook directory and sources any .sh files found.
# [Input] $1: hook_name (e.g., "post_install", "on_boot")
run_extension_hooks() {
    local hook_name="$1"
    # Commercial version mounted directory
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