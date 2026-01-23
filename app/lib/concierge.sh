#!/bin/bash

# [Why] To provide an interactive guide for user selection.
# [What] Displays a menu of available use-cases and captures user input.
# [Input] None (Interactive)
run_concierge_use_case() {
    log_info "💎 [Takumi] Select your creative environment:"
    
    local options=()
    local slugs=() 
    local i=1

    local namespaces=("core" "enterprise")
    
    # --- 1. Scan Candidates ---
    for ns in "${namespaces[@]}"; do
        # Building a Search Path
        local search_dir="${CONFIG_DIR}/takumi_meta/${ns}/recipes/use_cases"
        
        # Directory Existence Check
        if [ -d "$search_dir" ]; then
            # Read 'find' results with process substitution instead of temp file
            while IFS= read -r file; do
                # Skip blank and invalid lines
                [ -z "$file" ] && continue
                
                local slug=$(basename "$file" .json)
                local name=$(jq -r '.display_name // empty' "$file")
                [ -z "$name" ] && name="$slug"

                local label="$name"
                if [ "$ns" == "enterprise" ]; then label="[Enterprise] $name"; fi

                echo "  ($i) $label"
                
                options+=("$i")
                slugs+=("$slug")
                ((i++))
            done < <(find "$search_dir" -maxdepth 1 -name "*.json" | sort)
        else
            # Warning (for debugging)
            echo "Debug: Namespace dir not found: $search_dir"
        fi
    done

    # --- 2. Debug & Validation ---
    if [ ${#options[@]} -eq 0 ]; then
        log_error "No recipes found! Check your 'takumi_meta' directory structure."
        echo "Debug: Config Dir = $CONFIG_DIR"
        exit 1
    fi

    # --- 3. User Input (Robust) ---
    echo ""
    # Using 'read' with /dev/tty to ensure input even in some piped contexts
    read -n 1 -s -p "Enter number: " choice < /dev/tty
    echo ""

    # --- 4. Resolve Selection ---
    local selected_slug=""
    
    for idx in "${!options[@]}"; do
        if [ "${options[$idx]}" == "$choice" ]; then
            selected_slug="${slugs[$idx]}"
            break
        fi
    done

    # --- 5. Result ---
    if [ -n "$selected_slug" ]; then
        log_success "Selected: $selected_slug"
        state["use_case"]="$selected_slug"
    else
        log_warn "Invalid input: '$choice'"
        log_info "Available options: ${options[*]}"
        log_warn "Defaulting to 'create_and_dress_up_original_fashion'."
        state["use_case"]="create_and_dress_up_original_fashion"
    fi
}