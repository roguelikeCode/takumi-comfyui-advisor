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
# Stage 3: ASDF Installation (Auxiliary Tool Manager)
# ------------------------------------------------------------------------------
ENV ASDF_DIR=/opt/asdf
ENV PATH="${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"
RUN echo ">>> [INFO]  Installing ASDF..." && \
    git clone https://github.com/asdf-vm/asdf.git ${ASDF_DIR} --branch v0.14.0

# ------------------------------------------------------------------------------
# Stage 4: System Integration & Configuration (Shell, Conda, ASDF, Git, TOS, etc.)
# ------------------------------------------------------------------------------
ENV GIT_TERMINAL_PROMPT=0
RUN echo ">>> [INFO]  Initializing shell environment (Conda, ASDF, and Git)..." && \
    echo ">>> --- [1/4] Initializing Conda..." && \
    . ${CONDA_DIR}/etc/profile.d/conda.sh && \
    conda init bash && \
    echo ">>> --- [2/4] Initializing ASDF..." && \
    echo "# <<< Initialize ASDF <<<" >> ~/.bashrc && \
    echo ". ${ASDF_DIR}/asdf.sh" >> ~/.bashrc && \
    echo ">>> --- [3/4] Setting up Git and Conda (global configuration)..." && \
    git config --global url."https://".insteadOf git:// && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda config --set auto_activate false && \
    echo ">>> --- [4/4] Cleaning up Conda cache..." && \
    conda clean -afy

# ------------------------------------------------------------------------------
# Stage 5: Application Setup & Tool Installation
# ------------------------------------------------------------------------------
WORKDIR /app
COPY ./.asdfrc /root/.asdfrc
COPY ./.tool-versions /root/.tool-versions
COPY ./app ./
COPY ./app/config ./config/

RUN echo ">>> [INFO] Adding asdf plugins..." && \
    . ~/.bashrc && \
    asdf plugin add yq https://github.com/sudermanjr/asdf-yq.git && \
    echo ">>> [INFO] Installing asdf tools..." && \
    asdf install

# ------------------------------------------------------------------------------
# Stage 6: Finalization
# ------------------------------------------------------------------------------
CMD [ "bash", "-c", "source ~/.bashrc && exec bash" ]
