#!/bin/bash

# ==============================================================================
# Takumi System: Automated Integration Tests
#
# [Why] To verify the core functionality of the installer logic in a controlled environment.
# [What] Executes key functions (catalog fetching, merging) and validates the output artifacts.
# ==============================================================================

# --- Strict Mode ---
set -euo pipefail

# --- Import Libraries ---
# [Note] We directly load the library modules instead of the entry point script.
source /app/lib/utils.sh
source /app/lib/logger.sh
source /app/lib/installer.sh

# ==============================================================================
# Test Harness (Abstraction)
# ==============================================================================

# [Why] To standardize test case execution and reporting.
# [What] Runs a command, logs the step, and handles success/failure.
# [Input] $1: description, $2: command
run_test() {
    local description="$1"
    local command="$2"
    
    log_info ">>> Testing: ${description}..."
    
    if eval "$command"; then
        log_success "Pass."
    else
        log_error "Fail."
        exit 1
    fi
}

# [Why] To validate the integrity of generated JSON files.
# [What] Checks for file existence and valid JSON syntax using jq.
# [Input] $1: file_path
validate_json_artifact() {
    local file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        log_error "Artifact missing: $file_path"
        return 1
    fi

    if ! jq empty "$file_path" > /dev/null 2>&1; then
        log_error "Invalid JSON format: $file_path"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Test Cases
# ==============================================================================

test_catalog_fetching() {
    run_test "Fetching external catalogs" "fetch_external_catalogs"
}

test_catalog_merging() {
    run_test "Building merged catalog (custom_nodes)" 'build_merged_catalog "custom_nodes"'
}

test_artifact_integrity() {
    local target_file="${CACHE_DIR}/catalogs/custom_nodes_merged.json"
    run_test "Validating output JSON" "validate_json_artifact '$target_file'"
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    echo "========================================"
    echo "🧪 Takumi System: Automated Testing"
    echo "========================================"
    
    # Ensure environment is ready (from utils.sh)
    ensure_directories

    # Execute Test Suite
    test_catalog_fetching
    test_catalog_merging
    test_artifact_integrity

    echo ""
    log_success "🎉 All tests p