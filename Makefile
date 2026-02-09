SHELL := /bin/bash

# ==============================================================================
#  Takumi ComfyUI Advisor (OSS Edition)
# ==============================================================================

# [Config] Launcher (Secure Env Injection)
LAUNCHER := $(shell command -v dotenvx >/dev/null 2>&1 && echo "dotenvx run --" || echo "")

# [Core] The Unified Command Wrapper
# [Note] For Rootless Docker, the container runs as 'root' inside, which maps to the host user outside.
COMPOSE_CMD := $(LAUNCHER) docker compose

# Targets
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Takumi OSS Commands:"
	@echo ""
	@echo "  [Setup & Security]"
	@echo "    make setup-env    : Initialize .env and install utilities."
	@echo "    make encrypt      : Encrypt .env file for security."
	@echo ""
	@echo "  [Main]"
	@echo "  make build-oss    : Build the Docker image"
	@echo "  make install-oss  : Provision the environment (Install ComfyUI & Nodes)"
	@echo "  make run-oss      : Start the application stack"
	@echo "  make stop-oss     : Stop the application stack"
	@echo ""
	@echo "  [Development]"
	@echo "  make logs-oss     : View container logs"
	@echo "  make shell-oss    : Open a debug shell inside the container"
	@echo "  make clean-oss    : Factory Reset (Removes all data & containers)"

# ==============================================================================
# 1. Setup & Security
# ==============================================================================
.PHONY: setup-env encrypt

# [Setup]
setup-env:
	@echo ">>> Setting up environment..."
	@if [ ! -f .env ]; then \
		echo "  -> Creating .env from .env.example..."; \
		cp .env.example .env; \
		echo "  ✅ .env created. Please open it and set your HF_TOKEN."; \
	else \
		echo "  -> .env already exists. Skipping."; \
	fi
	@echo ">>> Checking for dotenvx (Encryption tool)..."
	@if ! command -v dotenvx >/dev/null 2>&1; then \
		echo "  -> dotenvx not found. Installing $(DOTENVX_VERSION)..."; \
		curl -sfS https://dotenvx.sh/install.sh | sh -s -- --version $(DOTENVX_VERSION); \
		echo "  ✅ dotenvx installed successfully."; \
	else \
		echo "  ✅ dotenvx is already installed."; \
	fi
# [Encryption]
encrypt:
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found. Please run 'make setup-env' first."; \
		exit 1; \
	fi
	@if command -v dotenvx >/dev/null 2>&1; then \
		echo ">>> Encrypting .env..."; \
		dotenvx encrypt; \
		echo "✅ Secrets encrypted. Keys generated in .env.keys"; \
	else \
		echo "❌ dotenvx not found. Please run 'make setup-env' first."; \
	fi

# ==============================================================================
# 1. Lifecycle Management
# ==============================================================================

# [Build]
build-oss:
	@echo ">>> Building OSS Image..."
	$(COMPOSE_CMD) build

# [Install]
# Flow: Build -> Start Infrastructure -> Execute Installer inside Container
install-oss: build-oss
	@echo ">>> [Step 1] Stopping everything to clear RAM..."
	$(COMPOSE_CMD) down
	
	@echo ">>> [Step 2] Running Installer in ISOLATION (Low Memory)..."
	@# --no-deps : Do not start Ollama (Saves ~3GB RAM)
	@# --rm      : Remove container after script finishes
	$(COMPOSE_CMD) run --rm --no-deps \
		-e SKIP_BRAIN=true \
		-e UV_CONCURRENT_DOWNLOADS=1 \
		-e UV_CONCURRENT_BUILDS=1 \
		comfyui bash /app/install.sh
	
	@echo ">>> [Step 3] Booting Full Stack..."
	$(COMPOSE_CMD) up -d
	@echo "✅ Installation Complete. ComfyUI is starting at http://localhost:8188"

# [Run]
# Just start the services. 'run.sh' inside the container handles the rest.
run-oss:
	@echo ">>> Starting Full Stack..."
	$(COMPOSE_CMD) up -d
	@echo "✅ Stack is running."
	@echo "   - ComfyUI: http://localhost:8188"

# [Stop]
stop-oss:
	@echo ">>> Stopping Stack..."
	$(COMPOSE_CMD) down

# ==============================================================================
# 2. Observability & Debugging
# ==============================================================================

# [Logs] Follow output
logs-oss:
	$(COMPOSE_CMD) logs -f

# [Shell] Debug Mode
# Uses 'run --rm' to create a disposable container attached to the network.
shell-oss:
	@echo ">>> Entering Debug Shell..."
	$(COMPOSE_CMD) run --rm --entrypoint bash comfyui


# ==============================================================================
# 3. Maintenance
# ==============================================================================

# [Emergency] Fix OOM (Exit Code 137)
# [Why] To prevent the kernel from killing the installer when RAM + Swap is full.
# [What] Creates a temporary 16GB swap file in the Host Linux (WSL2).
fix-memory:
	@echo ">>> 🧠 Allocating Emergency Swap (16GB)..."
	@# 既存のswapがあれば無効化して削除（エラーは無視）
	@-sudo swapoff /swapfile 2>/dev/null || true
	@-sudo rm -f /swapfile
	
	@# 16GB確保 (fallocateは高速です)
	@sudo fallocate -l 16G /swapfile
	@sudo chmod 600 /swapfile
	@sudo mkswap /swapfile
	@sudo swapon /swapfile
	
	@echo ">>> ✅ Memory expanded."
	@# 結果を表示 (Total Swapが増えていることを確認)
	@free -h

# [Update] Host System Security
# [Why] To keep the underlying OS (WSL2) and Docker Engine secure and up-to-date.
update-oss:
	@echo ">>> 🛡️  [Step 1] Updating Host System (apt)..."
	@sudo apt-get update && sudo apt-get upgrade -y
	@echo ">>> 🐳 [Step 2] Cleaning Docker System Garbage..."
	@# Removes stopped containers, unused networks, and dangling images to free disk space
	@docker system prune -f
	@echo "✅ Host system updated and cleaned."

# [Cache] Deep Clean & Rebuild
# [Why] To resolve build-time dependency issues by purging ALL caches.
cache-oss:
	@echo ">>> 🧹 [Step 1] Aggressive Cache Cleanup..."
	@# -a: Remove all unused build cache, not just dangling ones.
	@# -f: Force without prompt.
	@docker builder prune -af
	@docker image prune -f
	
	@echo ">>> 🏗️  [Step 2] Rebuilding Image (Fresh)..."
	$(COMPOSE_CMD) build --no-cache
	
	@echo "✅ Build cache purged and image renewed."

# [Clean] Factory Reset
# [Warning] This deletes ALL persistent volumes (Conda envs, models, output).
clean-oss:
	@echo ">>> ☢️  INITIATING FACTORY RESET..."
	@echo "   -> Stopping containers..."
	$(COMPOSE_CMD) down --remove-orphans --volumes
	@echo "   -> Sweeping artifacts..."
	@docker rm -f takumi-comfyui-oss takumi-ollama 2>/dev/null || true
	@echo "✅ System restored to factory settings."