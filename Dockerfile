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
# Stage 1: OS Core Environment Setup
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
# Stage 3: Installation & Application Setup (ASDF)
# ------------------------------------------------------------------------------
WORKDIR /app
COPY app/ .

COPY .tool-versions .

RUN asdf plugin-add miniconda https://github.com/asdf-community/asdf-miniconda.git && \
    asdf plugin-add yq https://github.com/tennashi/asdf-yq.git && \
    asdf install

# [重要] asdfでインストールしたツールのPATHをシェルに認識させる
# condaの初期化と有効化を行うための重要なステップ
RUN . ${ASDF_DIR}/asdf.sh && \
    conda init bash && \
    conda config --set auto_activate_base true

# ------------------------------------------------------------------------------
# Stage 4: Base Conda Environment Setup (Python Environment)
# ------------------------------------------------------------------------------
# シェルをcondaが有効な状態で起動するための `conda run` を使うか、
# もしくは bash -c 'source ~/.bashrc && command' のようにする。
# ここでは、将来の requirements.yml ファイルの設置場所を準備する。
# まず、環境定義ファイル群をコンテナにコピーする
COPY app/config/environments /app/config/environments

# ハードウェアに応じたベース環境を選択して構築する。
# ここでは、新しいGPU向けのcuda12をデフォルトとする。
# 将来的には、ビルド時の引数でこれを変更できるようにする。
RUN . ${ASDF_DIR}/asdf.sh && \
    conda env create \
      --file /app/config/base_components/core-tools.yml \
      --file /app/config/base_components/python/3.12.yml \
      --file /app/config/base_components/accelerator/cuda-12.yml

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