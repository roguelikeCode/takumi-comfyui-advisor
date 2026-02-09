#!/bin/bash

# [Why] To allows shell scripts to easily ask the Python AI (Gemma) questions.
# [What] Provides a bridge function to send prompts to the AI and display the response.
# [Input] $1: prompt
ask_takumi() {
    # [Fix] Isolation Mode (SKIP_BRAIN=true) の時は、AIへの相談をスキップする
    if [ "${SKIP_BRAIN:-false}" == "true" ]; then
        echo ">>> [Brain] Skipping AI consultation (Isolation Mode)."
        return
    fi
    
    local prompt="$1"
    local error_desc="${2:-}" # Optional second argument
    
    # Specify the location of the Python script (path inside the container)
    local script_path="/app/scripts/brain.py"
    
    log_info "Consulting The Takumi (Gemma 3)..."
    
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

# [Why] To connect to the external AI Brain (Ollama) and ensure the model exists.
# [What] 1. Waits for the HTTP endpoint (Sidecar). 2. Uses local CLI to trigger remote pull.
provision_brain() {
    # --- Configuration ---
    local model_name="gemma3:4b"
    local raw_host="${OLLAMA_HOST:-http://ollama:11434}"
    # Sanitize: Strip '/v1' suffix to ensure raw API access for curl/cli
    local target_host="${raw_host%/v1*}" 

    log_info "Initializing connection to AI Brain at ${target_host}..."

    # --- Phase 1: Health Check (Wait for Sidecar) ---
    local max_retries=10
    local count=0
    
    # Loop until connection is established
    while ! curl -s "${target_host}" > /dev/null; do
        sleep 2
        ((count++))
        if [ "$count" -ge "$max_retries" ]; then
            log_warn "Brain unreachable at ${target_host}. Skipping AI setup."
            return 0
        fi
        echo -n "."
    done
    echo "" # Newline for clean log

    # --- Phase 2: Model Provisioning (Remote Control) ---
    # [Note] In Microservices, we use the local 'ollama' CLI to control the remote 'ollama' server.
    
    if ! command -v ollama >/dev/null; then
        log_warn "Ollama CLI client not found. Skipping model verification."
        return 0
    fi

    # Point local CLI to the remote host context
    export OLLAMA_HOST="$target_host"

    if ollama list | grep -q "${model_name}"; then
        log_info "  -> Neural network '${model_name}' is active."
    else
        log_info "  -> Provisioning '${model_name}' (This may take time)..."
        if ! ollama pull "${model_name}"; then
            log_warn "Model pull failed."
            log_info "Hint: Try manually: 'docker exec -it takumi-ollama ollama pull ${model_name}'"
        else
            log_success "Brain upgrade complete: ${model_name}"
        fi
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