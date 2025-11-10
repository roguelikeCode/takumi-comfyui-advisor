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

RUN echo ">>> Downloading and installing Miniconda..." && \
    wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh

RUN echo ">>> Initializing Conda and accepting Terms of Service..." && \
    . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda init bash && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda config --set auto_activate false && \
    conda clean -afy

# ------------------------------------------------------------------------------
# Stage 3: ASDF Installation & System Integration (Auxiliary Tool Manager)
# ------------------------------------------------------------------------------
ENV ASDF_DIR=/opt/asdf
ENV PATH="${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"
ENV GIT_TERMINAL_PROMPT=0

# Add the asdf initialization command to `.bashrc`
RUN echo ">>> Installing and initializing ASDF, configuring Git..." && \
    git clone https://github.com/asdf-vm/asdf.git ${ASDF_DIR} --branch v0.14.0 && \
    echo "\n. ${ASDF_DIR}/asdf.sh" >> ~/.bashrc && \
    git config --global url."https://".insteadOf git://

# ------------------------------------------------------------------------------
# Stage 4: Application Setup & Tool Installation
# ------------------------------------------------------------------------------
WORKDIR /app
COPY ./.tool-versions .
COPY ./app ./
COPY ./app/config ./config/

RUN echo ">>> Installing tools specified in .tool-versions (e.g., yq)..."
RUN . ~/.bashrc && \
    asdf plugin add yq && \
    asdf install yq

# ------------------------------------------------------------------------------
# Stage 5: Finalization
#
# - Define the default command to be executed when the container starts.
# - For development, this will typically be an interactive shell.
# ------------------------------------------------------------------------------
# [思想] このイメージのデフォルトの役割は、開発とインストールのための「対話可能な工房」であること。
# そのため、起動時のコマンドはインタラクティブなシェルとする。
# コンテナ起動時に、conda環境が有効化されたbashを起動するように設定
CMD [ "bash", "-c", "source ~/.bashrc && exec bash" ]