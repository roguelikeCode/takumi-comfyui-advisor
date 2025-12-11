#!/bin/bash

# [Why] To provide an interactive guide for user selection.
# [What] Displays a menu of available use-cases and captures user input.

# [Input] None (Interactive)
run_concierge_use_case() {
    log_info "Your foundation is perfect. Now, let's select your specialized tools."
    
    echo ""
    echo "Please choose your primary use case:"
    echo "  (1) [Defaults] (Basic setup)"
    echo "  (2) Create & Dress Up Original Fashion (MagicClothing)"
    echo "  (3) AI Video Generation (AnimateDiff)"
    echo ""
    
    # Using 'read' with /dev/tty to ensure input even in some piped contexts
    read -n 1 -s -p "Enter number: " choice < /dev/tty
    echo ""

    local use_case_filename="defaults"

    case "$choice" in
        "1") use_case_filename="defaults" ;;
        "2") use_case_filename="create_and_dress_up_original_fashion" ;;
        "3") use_case_filename="animate_diff_video" ;;
        *)
            log_warn "Invalid selection. Proceeding with the default use-case: '${use_case_filename}'"
            ;;
    esac

    # Confirm selection
    local use_case_path="${CONFIG_DIR}/takumi_meta/recipes/use_cases/${use_case_filename}.json"
    
    if [ ! -f "$use_case_path" ]; then
        log_error "Asset manifest file for '${use_case_filename}' does not exist at ${use_case_path}."
        exit 1
    fi

    # Parse display name using jq
    local display_name
    display_name=$(jq -r '.display_name' "$use_case_path")

    echo ""
    log_info "You have selected: \"${display_name}\""
    echo "The following components will be installed:"
    
    # Preview components
    jq -r '.components[] | [.type, .source, .version] | @tsv' "$use_case_path" | \
    while IFS=$'\t' read -r type source version; do
        if [ "$version" == "null" ] || [ -z "$version" ]; then
            echo "  - [${type}] ${source}"
        else
            echo "  - [${type}] ${source} (${version})"
        fi
    done
    
    echo ""
    read -n 1 -s -p "Proceed with this plan? [Y/n]: " consent < /dev/tty
    echo ""

    if [[ "${consent,,}" == "n" ]]; then
        log_warn "Use-case installation aborted by user."
        exit 1
    fi

    # Update global state
    state["use_case"]=$use_case_filename
}