#!/bin/bash

# [Why] To provide an interactive guide for user selection.
# [What] Displays a menu of available use-cases and captures user input.
# [Input] None (Interactive)
run_concierge_use_case() {
    log_info "💎 [Takumi] Select your creative environment:"
    local options=()
    local slugs=() 
    local i=1

    local search_dir="/app/external/takumi-registry/recipes/use_cases"
    
    # --- 1. Scan Candidates ---
    if [ -d "$search_dir" ]; then
        # Read 'find' results with process substitution
        while IFS= read -r file; do
            # Skip blank and invalid lines[ -z "$file" ] && continue
            
            local slug
            slug=$(basename "$file" .json)
            
            local name
            # `jq` should not throw an error if it fails, and should safely accept an empty string.
            name=$(jq -r '.display_name // empty' "$file" 2>/dev/null || true)
            
            # Space Trap avoidance & Strict Mode countermeasures
            if [ -z "${name:-}" ]; then
                name="$slug"
            fi
            
            echo "  ($i) $name"
            options+=("$i")
            slugs+=("$slug")
            ((i++))
        done < <(find "$search_dir" -maxdepth 1 -name "*.json" | sort)
    fi

    # --- 2. Debug & Validation ---
    if [ ${#options[@]} -eq 0 ]; then
        log_error "No recipes found! Check your 'takumi_meta' directory structure."
        echo "Debug: Searched Directory = $search_dir"
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
        log_warn "Defaulting to '00_infrastructure_only'."
        state["use_case"]="00_infrastructure_only"
    fi
}