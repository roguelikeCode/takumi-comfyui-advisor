#!/bin/bash

# [Why] To verify hardware capabilities and configure the environment accordingly.
# [What] Detects NVIDIA GPU, CUDA version, and sets global state variables.
# [Input] None (Uses system commands: nvidia-smi)
detect_gpu_environment() {
    log_info "Diagnosing your hardware environment..."
    
    # Check for nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        local smi_output
        smi_output=$(nvidia-smi)

        # Extract CUDA Version (e.g., "12.4" -> "12")
        if [[ $smi_output =~ CUDA\ Version:\ ([0-9]+\.[0-9]+) ]]; then
            local cuda_version="${BASH_REMATCH[1]}"
            local cuda_major_version="${cuda_version%%.*}"
            
            log_success "NVIDIA GPU detected. CUDA Driver Version: $cuda_version"
            
            # Set global state
            state["detected_cuda_major"]=$cuda_major_version
            state["detected_accelerator"]="cuda"
            return 0
        fi
    fi
    
    # Fallback to CPU
    log_warn "No compatible NVIDIA GPU with CUDA drivers found."
    log_info "Proceeding with CPU-only configuration."
    state["detected_accelerator"]="cpu"
    return 0
}

# [Why] Select the optimal environment YAML based on hardware availability.
# [What] Checks for nvidia-smi. Returns 'cuda_12_4' (Standard) or 'cpu'.
# [Output] String (Environment ID)
detect_optimal_environment() {
    # 1. Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        # Future-proofing: Logic for RTX 50 series (CUDA 13) can go here.
        # local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        
        echo "cuda_12_4"
    else
        echo "cpu"
    fi
}