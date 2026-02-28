# ==============================================================================
# Takumi Foundry - Universal Development Environment v5.1 (Miniforge-based)
#
# Maintainer: Yamato Watase
# Description: This Dockerfile defines a universal, asdf-based environment.
#              It delegates all runtime version management to a single,
#              declarative `.tool-versions` file, embracing the principle of
#              Infrastructure as Code.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Base Image & System Setup
# ------------------------------------------------------------------------------
FROM ubuntu:24.04

# [Why] This ensures compatibility with conda initialization scripts and pipefail option.
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # --- System Utilities ---
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    unzip \
    bzip2 \
    zstd \
    sudo \
    gosu \
    # --- Build Essentials (For compiling C++ extensions) ---
    build-essential \
    cmake \
    pkg-config \
    # --- Python Basics (For uv/pip bootstrapping) ---
    python3-pip \
    # --- Graphics & UI Libraries (Required by OpenCV/ComfyUI) ---
    libgl1 \
    libglib2.0-0 \
    libcairo2-dev \
    libsndfile1 \
    # --- Cleanup (Reduce image size) ---
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 2. User & Permissions
# ------------------------------------------------------------------------------
# [Why] To match the Host OS user ID and prevent "Permission Denied" errors on mounted volumes.
ARG TAKUMI_UID=9000
ARG TAKUMI_GID=9000

RUN echo ">>> Creating 'takumi' user with UID=${TAKUMI_UID} GID=${TAKUMI_GID}..." && \
    groupadd --gid ${TAKUMI_GID} takumi || true && \
    useradd --uid ${TAKUMI_UID} --gid ${TAKUMI_GID} --shell /bin/bash --create-home takumi && \
    usermod -aG sudo takumi && \
    echo "takumi ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ------------------------------------------------------------------------------
# 3. Universal Tools Installation
# ------------------------------------------------------------------------------
ARG TARGETARCH
COPY ./app/config/takumi_meta/core/infra/architectures.json /tmp/architectures.json

ENV OLLAMA_VERSION="0.17.4"
ENV UV_VERSION="0.10.7"
ENV MINIFORGE_VERSION="26.1.0-0"
ENV CONDA_DIR="/opt/conda"
ENV PATH="${CONDA_DIR}/bin:${PATH}"

# Architecture Decision Logic
RUN echo '#!/bin/sh' > /usr/local/bin/detect_arch && \
    echo 'ARCH=$(uname -m)' >> /usr/local/bin/detect_arch && \
    echo 'if [ "$ARCH" = "x86_64" ]; then echo "amd64";' >> /usr/local/bin/detect_arch && \
    echo 'elif [ "$ARCH" = "aarch64" ]; then echo "arm64";' >> /usr/local/bin/detect_arch && \
    echo 'else echo "$ARCH"; fi' >> /usr/local/bin/detect_arch && \
    chmod +x /usr/local/bin/detect_arch

# --- Ollama (The Brain) ---
# [Why] To run local LLMs (Gemma) for the Chat UI.
# [Note] Official install.sh fails due to systemd dependencies in Docker.
# [Note] We download the script, patch 'systemctl' to 'echo' (bypass), and run it.
RUN TARGETARCH=$(detect_arch) && \
    echo ">>> Installing Ollama v${OLLAMA_VERSION} for ${TARGETARCH}..." && \
    # 1. Parse architecture specific binary/checksum from JSON
    OLLAMA_BINARY=$(jq -r ".ollama[\"${OLLAMA_VERSION}\"][\"${TARGETARCH}\"].binary" /tmp/architectures.json) && \
    OLLAMA_CHECKSUM=$(jq -r ".ollama[\"${OLLAMA_VERSION}\"][\"${TARGETARCH}\"].checksum" /tmp/architectures.json) && \
    # 2. Download and Verify
    wget "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/${OLLAMA_BINARY}" -O /tmp/${OLLAMA_BINARY} && \
    echo "${OLLAMA_CHECKSUM}  /tmp/${OLLAMA_BINARY}" | sha256sum -c - && \
    # 3. Install (Extracting the `.tar.zst`)
    tar -I zstd -C /usr/local -xf /tmp/${OLLAMA_BINARY} && \
    # 4. Cleanup
    rm /tmp/${OLLAMA_BINARY}

# --- uv (The Fast Installer) ---
# [Why] To speed up pip package installations.
RUN TARGETARCH=$(detect_arch) && \
    echo ">>> Installing uv v${UV_VERSION} for ${TARGETARCH}..." && \
    # 1. Parse architecture specific binary/checksum from JSON
    UV_BINARY=$(jq -r ".uv[\"${UV_VERSION}\"][\"${TARGETARCH}\"].binary" /tmp/architectures.json) && \
    UV_CHECKSUM=$(jq -r ".uv[\"${UV_VERSION}\"][\"${TARGETARCH}\"].checksum" /tmp/architectures.json) && \
    # 2. Download and Verify
    wget "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_BINARY}" -O /tmp/${UV_BINARY} && \
    echo "${UV_CHECKSUM}  /tmp/${UV_BINARY}" | sha256sum -c - && \
    # 3. Install (Extracting the `.tar.zst`)
    tar -C /usr/local/bin --strip-components=1 --wildcards -xzf /tmp/${UV_BINARY} "*/uv" "*/uvx" && \
    # 4. Cleanup
    rm /tmp/${UV_BINARY}

# --- Miniforge (The Environment Manager) ---
# [Why] To manage Python versions and CUDA dependencies without licensing issues (unlike Anaconda).
RUN TARGETARCH=$(detect_arch) && \
    echo ">>> Installing Miniforge ${MINIFORGE_VERSION} for ${TARGETARCH}..." && \
    # 1. Parse architecture specific binary/checksum from JSON
    MINIFORGE_BINARY=$(jq -r ".miniforge[\"${MINIFORGE_VERSION}\"][\"${TARGETARCH}\"].binary" /tmp/architectures.json) && \
    MINIFORGE_CHECKSUM=$(jq -r ".miniforge[\"${MINIFORGE_VERSION}\"][\"${TARGETARCH}\"].checksum" /tmp/architectures.json) && \
    # 2. Download and Verify
    wget "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_BINARY}" -O /tmp/miniforge.sh && \
    echo "${MINIFORGE_CHECKSUM}  /tmp/miniforge.sh" | sha256sum -c - && \
    # 3. Install
    /bin/bash /tmp/miniforge.sh -b -p $CONDA_DIR && \
    rm /tmp/miniforge.sh && \
    # 4. Initialize
    . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda init bash && \
    conda config --set auto_activate false && \
    # 5. Cleanup
    conda clean -afy && \
    rm /tmp/architectures.json /usr/local/bin/detect_arch

# ------------------------------------------------------------------------------
# 4. Application Setup
# ------------------------------------------------------------------------------
WORKDIR /app

# [Security] 1. Create Writable Directories (Takumi Owned)
RUN mkdir -p \
    /app/scripts \
    /app/cache \
    /app/external \
    /app/logs \
    /app/storage \
    /app/temp && \
    chown -R takumi:takumi /app

# [Security] 2. Immutable Application Core (Root Owned)
COPY app/ .
COPY scripts/ ./scripts/

# [Security] 3. Script Permissions
RUN chmod 755 \
    /app/scripts/entrypoint.sh \
    /app/scripts/run.sh \
    /app/install.sh

# ------------------------------------------------------------------------------
# 5. Finalization
# ------------------------------------------------------------------------------
# [Optimization] Prevent .pyc generation (Essential for Read-Only roots)
ENV PYTHONDONTWRITEBYTECODE=1

# [Gatekeeper] Initialize as Root to fix permissions, then drop to User
ENTRYPOINT [ "/app/scripts/entrypoint.sh" ]

# [Engine] Default launch command
CMD [ "bash", "/app/scripts/run.sh" ]
