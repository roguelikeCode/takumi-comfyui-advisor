# ==============================================================================
# Takumi-ComfyUI: The Perfect Foundry - Base Image v1.0
#
# Maintainer: Yamato Watase
# Description: This Dockerfile defines the foundational environment for the
#              Takumi project, ensuring perfect reproducibility. It handles
#              Phase 1 (OS, Build Tools, Conda) of the installation.
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Base Environment Setup
#
# - To ensure security, we will use Ubuntu 24.04 LTS as the base.
# - Install essential build tools and utilities.
# ------------------------------------------------------------------------------
FROM ubuntu:24.04

# [思想] ビルド中の対話型プロンプトを完全に無効化し、自動化を妨げるあらゆる曖昧さを排除する。
ENV DEBIAN_FRONTEND=noninteractive

# [思想] レイヤー数を最小化し、イメージサイズを最適化するため、RUN命令は論理的な単位で結合する。
# C++ビルドツール、ネットワークツール、アーカイブツールなど、工房の基礎となる道具を一度に揃える。
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    bzip2 \
    unzip \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Stage 2: Miniconda Installation
#
# - Install a self-contained Python environment manager to avoid polluting
#   the system's Python. This is the core of our dependency management.
# ------------------------------------------------------------------------------
# [思想] システムのPythonを汚染せず、完全に独立したPython環境を支配するため、Minicondaを導入する。
# インストール先は/opt/condaとし、責務を明確に分離する。
ENV CONDA_DIR /opt/conda
ENV PATH $CONDA_DIR/bin:$PATH

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_DIR && \
    rm ~/miniconda.sh && \
    conda clean -afy

# ------------------------------------------------------------------------------
# Stage 3: yq (YAML/JSON Processor) Installation
#
# - Install yq, a powerful tool for manipulating YAML and JSON files.
#   This is the "chisel and hammer" for our declarative configuration files.
# ------------------------------------------------------------------------------
# [思想] 宣言的な設定ファイルを扱うための、最も強力な道具`yq`を導入する。
# aptで古いバージョンを導入するリスクを避け、公式サイトから最新の安定版バイナリを直接取得し、PATHの通った場所に配置する。
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# ------------------------------------------------------------------------------
# Stage 4: Application Setup
#
# - Set up the working directory and copy the application source code.
# - This stage is placed later to leverage Docker's layer caching.
# ------------------------------------------------------------------------------
# [思想] 変更頻度の高いアプリケーションコードのコピーは、ビルドプロセスの最後に配置する。
# これにより、Dockerのレイヤーキャッシュが最大限に活用され、再ビルドが高速化される。
WORKDIR /app

# まず、後続の処理で必要になるファイルだけをコピーする
# (例: install.shでConda環境を作るなら、そのための設定ファイルなど)
# 今回はシンプルに全コピーするが、将来的には最適化の余地がある。
COPY . .

# ------------------------------------------------------------------------------
# Stage 5: Finalization
#
# - Define the default command to be executed when the container starts.
# - For development, this will typically be an interactive shell.
# ------------------------------------------------------------------------------
# [思想] このイメージのデフォルトの役割は、開発とインストールのための「対話可能な工房」であること。
# そのため、起動時のコマンドはインタラクティブなシェルとする。
CMD [ "/bin/bash" ]