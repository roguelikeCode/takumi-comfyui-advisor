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
    # --- Network & Version Control ---
    curl \
    wget \
    git \
    # --- Python Build Dependencies ---
    libssl-dev \
    libffi-dev \
    libncurses5-dev \
    libreadline-dev \
    libbz2-dev \
    liblzma-dev \
    # --- System Libraries for GUI/Graphics ---
    libgl1-mesa-glx \
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
# Stage 2: ASDF (The Universal Tool Version Manager)
# ------------------------------------------------------------------------------
RUN git clone https://github.com/asdf-vm/asdf.git /opt/asdf --branch v0.14.0
ENV ASDF_DIR=/opt/asdf
ENV PATH="${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"

# ------------------------------------------------------------------------------
# Stage 3: Installation & Application Setup (via ASDF)
# ------------------------------------------------------------------------------
WORKDIR /app

COPY .tool-versions .

RUN asdf plugin-add miniconda https://github.com/asdf-community/asdf-miniconda.git && \
    asdf plugin-add yq https://github.com/tennashi/asdf-yq.git && \
    asdf install

# ------------------------------------------------------------------------------
# Stage 4: Conda Environment Initialization & Base Environment Setup (Python Environment)
# ------------------------------------------------------------------------------
COPY app/ .

# condaの初期化とベース環境の構築を、一連の正しい流れで実行する
RUN . ${ASDF_DIR}/asdf.sh && \
    # ステップ1: condaを現在のシェルと将来のシェルのために初期化する
    conda init bash && \
    conda config --set auto_activate_base false && \
    # ステップ2: 初期化した設定を現在のシェルに即時反映させる
    source ~/.bashrc && \
    # ステップ3: 初期化が完了したcondaを使って、ベース環境を構築する
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
CMD [ "bash", "-c", "source ~/.bashrc && conda activate base && exec bash" ]