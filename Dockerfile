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
# Stage 1: OS Environment Setup
# ------------------------------------------------------------------------------
FROM ubuntu:24.04
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # --- Core Build System ---
    build-essential \
    cmake \
    golang-go \
    # --- Python (for uv) ---
    python3-pip \
    # --- Network & Version Control ---
    curl \
    wget \
    git \
    # --- System Libraries for GUI/Graphics (required by OpenCV, etc.) ---
    libgl1 \
    libglib2.0-0 \
    # --- SSL/TLS Trust Store ---
    ca-certificates \
    # --- Archive Utilities ---
    bzip2 \
    unzip \
    # --- Cleanup ---
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG TAKUMI_UID=9000
ARG TAKUMI_GID=9000
RUN echo ">>> Creating 'takumi' user with UID=${TAKUMI_UID} GID=${TAKUMI_GID}..." && \
    groupadd --gid ${TAKUMI_GID} takumi || true && \
    useradd --uid ${TAKUMI_UID} --gid ${TAKUMI_GID} --shell /bin/bash --create-home takumi && \
    usermod -aG sudo takumi && \
    echo "takumi ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ------------------------------------------------------------------------------
# Stage 2: Universal Tool Installation
# ------------------------------------------------------------------------------
ARG TARGETARCH
COPY ./app/config/foundation_components/architectures.json /tmp/architectures.json

# --- yq (Bootstrap Tool) ---
ENV YQ_VERSION=v4.48.2
RUN echo ">>> --- [1/3] Installing yq ${YQ_VERSION} for arch: ${TARGETARCH}..." && \
    YQ_BLOCK=$(sed -n "/\"yq\":/,/}/p" /tmp/architectures.json | \
               sed -n "/\"${YQ_VERSION}\":/,/}/p" | \
               sed -n "/\"${TARGETARCH}\":/,/}/p") && \
    echo ">>> --- [2/3] Extracting the 'binary' and 'checksum' values..." && \
    YQ_BINARY=$(echo "${YQ_BLOCK}" | grep '"binary":' | awk -F '"' '{print $4}') && \
    YQ_CHECKSUM=$(echo "${YQ_BLOCK}" | grep '"checksum":' | awk -F '"' '{print $4}') && \
    echo ">>> --- [3/3] Checking security" && \
    echo "Binary: ${YQ_BINARY}, Checksum: ${YQ_CHECKSUM}" && \
    wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /usr/local/bin/yq && \
    echo "${YQ_CHECKSUM}  /usr/local/bin/yq" | sha256sum -c - && \
    chmod +x /usr/local/bin/yq

# --- uv (Fast Python Package Installer) ---
RUN echo ">>> Installing uv (via pip)..." && \
    pip install uv --break-system-packages

# --- Miniforge (Core Python Environment) ---
ENV MINIFORGE_VERSION=25.9.1-0
ENV CONDA_DIR=/opt/conda
ENV PATH="${CONDA_DIR}/bin:${PATH}"
RUN echo ">>> --- [1/3] Installing Miniforge ${MINIFORGE_VERSION} for arch: ${TARGETARCH}..." && \
    MINIFORGE_BINARY=$(yq -r ".miniforge.\"${MINIFORGE_VERSION}\".\"${TARGETARCH}\".binary" /tmp/architectures.json) && \
    MINIFORGE_CHECKSUM=$(yq -r ".miniforge.\"${MINIFORGE_VERSION}\".\"${TARGETARCH}\".checksum" /tmp/architectures.json) && \
    echo ">>> --- [2/3] Checking security" && \
    wget "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_BINARY}" -O /tmp/miniforge.sh && \
    echo "${MINIFORGE_CHECKSUM}  /tmp/miniforge.sh" | sha256sum -c - && \
    /bin/bash /tmp/miniforge.sh -b -p $CONDA_DIR && \
    rm /tmp/miniforge.sh && \
    echo ">>> --- [3/3] Initializing Conda..." && \
    . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda init bash && \
    conda config --set auto_activate false && \
    conda clean -afy && \
    rm /tmp/architectures.json

# ------------------------------------------------------------------------------
# Stage 3: Application Setup
# ------------------------------------------------------------------------------
WORKDIR /app
COPY ./app ./
COPY ./app/config ./config/

# ------------------------------------------------------------------------------
# Stage 4: Finalization
# ------------------------------------------------------------------------------
CMD [ "bash" ]
