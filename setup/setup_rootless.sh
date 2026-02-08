#!/bin/bash

# ==============================================================================
# Takumi Sovereign Node Setup
#
# [Why] To establish a Linux-native, Rootless Docker environment with GPU support.
# [What] Removes Docker Desktop/System Docker and installs Rootless Docker.
# [Target] WSL2 (Ubuntu) / Native Linux
# ==============================================================================

set -e

# --- Colors ---
BLUE='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

log_info() { echo -e "${BLUE}>>> $1${RESET}"; }
log_warn() { echo -e "${YELLOW}WARNING: $1${RESET}"; }
log_success() { echo -e "${GREEN}SUCCESS: $1${RESET}"; }

# --- 0. Confirmation ---
clear
echo -e "${RED}============================================================${RESET}"
echo -e "${RED}   DANGER: SYSTEM MODIFICATION ALERT                        ${RESET}"
echo -e "${RED}============================================================${RESET}"
echo "This script will:"
echo "  1. 🗑️  UNINSTALL Docker Desktop and System Docker."
echo "  2. ⚙️  INSTALL Native Docker Engine & NVIDIA Container Toolkit."
echo "  3. 🛡️  SETUP Rootless Docker (User Mode)."
echo ""
echo "Any existing containers/images will be deleted."
echo "Make sure you have backed up your data."
echo ""
read -p "Are you ready to proceed? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 1
fi

# --- 1. Cleanup (The Purge) ---
log_info "Step 1: Cleaning up old Docker environments..."

# Stop services
sudo systemctl stop docker.service 2>/dev/null || true
sudo systemctl stop docker.socket 2>/dev/null || true
sudo killall dockerd 2>/dev/null || true

# Remove artifacts
sudo apt-get remove --purge -y docker-desktop docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /etc/docker
sudo rm -f /var/run/docker.sock

# Remove user configs
sudo rm -f /root/.docker/config.json
rm -f ~/.docker/config.json

# Remove dockremap if exists
sudo deluser dockremap 2>/dev/null || true
sudo delgroup dockremap 2>/dev/null || true

# --- 2. Repositories & Dependencies ---
log_info "Step 2: Setting up repositories..."

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg uidmap dbus-user-session

# Docker Repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# NVIDIA Repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# --- 3. Installation ---
log_info "Step 3: Installing engines..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit

# Disable system-wide docker immediately
sudo systemctl disable --now docker.service docker.socket

# --- 3.5. NVIDIA Configuration (Critical for Rootless) ---
log_info "Step 3.5: Configuring NVIDIA for Rootless..."

# Generate a configuration file (if it doesn't already exist)
if [ ! -f /etc/nvidia-container-runtime/config.toml ]; then
    sudo nvidia-ctk runtime configure --runtime=docker --config=/etc/nvidia-container-runtime/config.toml
fi

# Disable `cgroup`` control (avoiding permission errors in `rootless``)
sudo sed -i 's/^#no-cgroups = false/no-cgroups = true/g' /etc/nvidia-container-runtime/config.toml
sudo sed -i 's/^no-cgroups = false/no-cgroups = true/g' /etc/nvidia-container-runtime/config.toml

log_success "NVIDIA Runtime configured (no-cgroups)."

# --- 4. Rootless Setup ---
log_info "Step 4: Activating Rootless Mode..."

# Run official installer
curl -fsSL https://get.docker.com/rootless | sh

# --- 5. Configuration (Env & GPU) ---
log_info "Step 5: Configuring environment..."

# 5.1 Update .bashrc (Idempotent)
if ! grep -q "DOCKER_HOST" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo '# --- Takumi Rootless Docker ---' >> ~/.bashrc
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    # Use dynamic ID for portability
    echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.bashrc
    log_success "Environment variables added to ~/.bashrc"
fi

# 5.2 Configure Daemon for NVIDIA
mkdir -p ~/.config/docker
cat <<EOF > ~/.config/docker/daemon.json
{
  "runtimes": {
    "nvidia": {
      "path": "/usr/bin/nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
EOF

# --- 6. Restart & Verify ---
log_info "Step 6: Restarting services..."

# Reload systemd user daemon
systemctl --user daemon-reload
systemctl --user restart docker

# Wait for socket
sleep 5

log_info "Testing GPU connection..."
# Use full path to ensure we use the rootless docker client
~/bin/docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

echo ""
log_success "🎉 Sovereign Node Setup Complete!"
echo "Please run 'source ~/.bashrc' or restart your terminal."