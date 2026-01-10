#!/bin/bash

# [Why] To allows shell scripts to easily ask the Python AI (Gemma) questions.
# [What] Provides a bridge function to send prompts to the AI and display the response.

# [Input] $1: prompt
ask_takumi() {
    local prompt="$1"
    local error_desc="${2:-}" # Optional second argument
    local script_path="${APP_ROOT}/scripts/brain.py"
    
    log_info "Consulting The Takumi (Gemma 2)..."
    
    if [ -f "$script_path" ]; then
        local response
        # Call Python brain
        if [ -n "$error_desc" ]; then
            response=$(python3 "$script_path" "$prompt" "$error_desc")
        else
            response=$(python3 "$script_path" "$prompt")
        fi
        
        echo ""
        echo -e "${COLOR_BLUE}--- The Takumi's Advice ---${COLOR_RESET}"
        echo "$response"
        echo -e "${COLOR_BLUE}---------------------------${COLOR_RESET}"
        echo ""
    else
        log_warn "Brain script not found at $script_path. Skipping AI consultation."
    fi
}

# [Why] To attempt a command and ask AI for help if it fails.
# [Input] $1: command_string, $2: description
try_with_ai() {
    local command="$1"
    local description="${2:-No description}"
    
    log_info "$description"
    
    if eval "$command"; then
        return 0
    else
        local exit_code=$?
        log_error "Command failed with exit code $exit_code."
        
        local prompt="The following command failed.
Command: '$command'
Description: $description
Exit Code: $exit_code

You are an expert engineer. Please provide concise advice in English (3 lines max) on the cause and solution in a Docker/Linux environment."

        ask_takumi "$prompt" "Command failed: $command (Exit $exit_code)"
        return $exit_code
    fi
}

# [Why] To provide detailed context to AI when complex installations fail.
# [Input] $1: error_msg, $2: context_data
consult_ai_on_complex_failure() {
    local error_msg="$1"
    local context_data="$2"
    
    log_error "$error_msg"
    
    local prompt="The following installation process failed.
Error: $error_msg
Context:
$context_data

Possible causes include dependency conflicts or system requirements.
Please provide technical advice in English to resolve this situation."

    ask_takumi "$prompt" "Complex Failure: $error_msg"
}