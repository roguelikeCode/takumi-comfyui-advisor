# ==============================================================================
# Takumi Foundry - Universal Development Environment v3.4 (Final)
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
    # --- Network & Version Control ---
    curl \
    wget \
    git \
    # --- Python Build Dependencies (for asdf) ---
    libssl-dev \
    libffi-dev \
    libncurses5-dev \
    libreadline-dev \
    libbz2-dev \
    liblzma-dev \
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

# ------------------------------------------------------------------------------
# Stage 2: Miniconda Installation (Python Environment Manager)
# ------------------------------------------------------------------------------
ENV CONDA_DIR=/opt/conda
ENV PATH="${CONDA_DIR}/bin:${PATH}"
RUN echo ">>> [INFO]  Downloading and installing Miniconda..." && \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh

# ------------------------------------------------------------------------------
# Stage 3: Tool Installation (yq, Cross-Platform and Secure)
# ------------------------------------------------------------------------------
ARG TARGETARCH
ENV YQ_VERSION=v4.48.2
COPY ./app/config/foundation_components/architectures.json /tmp/architectures.json
RUN echo ">>> --- [1/5] Installing yq ${YQ_VERSION} for arch: ${TARGETARCH} from DB..." && \
    YQ_BLOCK=$(sed -n "/\"yq\":/,/}/p" /tmp/architectures.json | \
               sed -n "/\"${YQ_VERSION}\":/,/}/p" | \
               sed -n "/\"${TARGETARCH}\":/,/}/p") && \
    echo ">>> --- [2/5] Extracting the 'binary' and 'checksum' values..." && \
    YQ_BINARY=$(echo "${YQ_BLOCK}" | grep '"binary":' | awk -F '"' '{print $4}') && \
    YQ_CHECKSUM=$(echo "${YQ_BLOCK}" | grep '"checksum":' | awk -F '"' '{print $4}') && \
    echo ">>> --- [3/5] Ensuring safety..." && \
    if [ -z "${YQ_BINARY}" ] || [ -z "${YQ_CHECKSUM}" ]; then \
        echo "ERROR: Could not parse yq details from architectures.json for arch '${TARGETARCH}'" >&2; \
        exit 1; \
    fi && \
    echo ">>> --- [4/5] Checking security" && \
    echo "Binary: ${YQ_BINARY}, Checksum: ${YQ_CHECKSUM}" && \
    wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /usr/local/bin/yq && \
    echo "${YQ_CHECKSUM}  /usr/local/bin/yq" | sha256sum -c - && \
    chmod +x /usr/local/bin/yq && \
    echo ">>> --- [5/5] Cleaning up cache..." && \
    rm /tmp/architectures.json

# ------------------------------------------------------------------------------
# Stage 4: System Integration & Configuration (Shell, Conda, Git, TOS, etc.)
# ------------------------------------------------------------------------------
ENV GIT_TERMINAL_PROMPT=0
RUN echo ">>> [INFO]  Initializing shell environment (Conda and Git)..." && \
    echo ">>> --- [1/3] Initializing Conda..." && \
    . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda init bash && \
    echo ">>> --- [2/3] Setting up Git and Conda (global configuration)..." && \
    git config --global url."https://".insteadOf git:// && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda config --set auto_activate false && \
    echo ">>> --- [3/3] Cleaning up Conda cache..." && \
    conda clean -afy

# ------------------------------------------------------------------------------
# Stage 5: Application Setup
# ------------------------------------------------------------------------------
WORKDIR /app
COPY ./app ./
COPY ./app/config ./config/

# ------------------------------------------------------------------------------
# Stage 6: Finalization
# ------------------------------------------------------------------------------
CMD [ "bash", "-c", "source ~/.bashrc && exec bash" ]
