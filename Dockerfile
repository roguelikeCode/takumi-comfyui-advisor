# ==============================================================================
# Takumi Foundry - Universal Development Environment v2.0
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

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh && \
    conda clean -afy && \
    conda init bash && \
    conda config --set auto_activate_base false

# ------------------------------------------------------------------------------
# Stage 3: ASDF Installation & Git Configuration (Auxiliary Tool Manager)
# ------------------------------------------------------------------------------
# asdf本体のインストール
RUN git clone https://github.com/asdf-vm/asdf.git /opt/asdf --branch v0.14.0
ENV ASDF_DIR=/opt/asdf
ENV PATH="${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"

# [修正] gitが対話的な認証を試みないように、ビルド環境全体で永続的に設定する
ENV GIT_TERMINAL_PROMPT=0
RUN git config --global url."https://".insteadOf git://

# ------------------------------------------------------------------------------
# Stage 4: Application Setup & Tool Installation
# ------------------------------------------------------------------------------
WORKDIR /app
COPY .tool-versions .
COPY app ./

# asdfを使ってyqをインストールする
# 前のステージでgitの設定が完了しているため、ここではasdfのコマンドに集中できる
RUN asdf plugin add yq && \
    asdf install yq

# Condaのベース環境を構築する
RUN . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda env create \
      --file /app/config/base_components/accelerator/cuda-12.yml \
      --file /app/config/base_components/python/3.12.yml \
      --file /app/config/base_components/core-tools.yml

# ------------------------------------------------------------------------------
# Stage 5: Finalization
#
# - Define the default command to be executed when the container starts.
# - For development, this will typically be an interactive shell.
# ------------------------------------------------------------------------------
# [思想] このイメージのデフォルトの役割は、開発とインストールのための「対話可能な工房」であること。
# そのため、起動時のコマンドはインタラクティブなシェルとする。
# コンテナ起動時に、conda環境が有効化されたbashを起動するように設定
CMD [ "bash", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate base && exec bash" ]