SHELL := /bin/bash

# ==============================================================================
# Configuration & Targets
# ==============================================================================

# [Launcher] Zero-Trust Env Injection
LAUNCHER := $(shell command -v doppler >/dev/null 2>&1 && echo "doppler run --" || echo "")

# [Core] The Unified Command Wrapper
# [Note] For Rootless Docker, the container runs as 'root' inside, which maps to the host user outside.
COMPOSE_CMD := $(LAUNCHER) docker compose

# [Why] Containers to sweep during reset
CORE_CONTAINERS := takumi-comfyui-oss takumi-proxy takumi-ollama

# [Why] Directories to vaporize during Factory Reset
# [Note] 'storage/ollama' is intentionally EXCLUDED to prevent re-downloading LLM models.
PURGE_DIRS := \
	external/ComfyUI \
	storage/envs \
	storage/pkgs \
	storage/cache \
	storage/receipts

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
.PHONY: setup-oss

# [Setup]
setup-oss:
	@echo ">>> Verifying Doppler Connection..."
	@doppler whoami >/dev/null 2>&1 || (echo "❌ Please run 'doppler login' first." && exit 1)
	@echo "✅ Doppler is ready."

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
	@echo ">>> [Step 1] Waking up Infrastructure..."
	@# --wait: Wait for Ollama's health check (startup completion) before proceeding
	$(COMPOSE_CMD) up -d --wait

	@echo ">>> [Step 2] Running Installer (Full Power)..."
	@# Run a script inside an already running container
	$(COMPOSE_CMD) exec --user takumi comfyui bash /app/install.sh

	@echo ">>> [Step 3] Restarting Runtime (Apply Changes)..."
	$(COMPOSE_CMD) restart comfyui
	@echo "✅ Installation Complete. Next, (make run-oss)."

# [Run]
# Just start the services. 'run.sh' inside the container handles the rest.
run-oss:
	@echo ">>> Starting Full Stack..."
	$(COMPOSE_CMD) up -d
	@echo ">>> 🛡️  Verifying Zero-Trust Network (Tailscale)..."
	@connected=0; \
	for i in 1 2 3 4 5; do \
		if $(LAUNCHER) docker exec takumi-tailscale tailscale status 2>/dev/null | grep -q "takumi-vpn"; then \
			connected=1; \
			break; \
		fi; \
		echo -n "."; \
		sleep 1; \
	done; \
	echo ""; \
	if [ $$connected -eq 0 ]; then \
		echo -e "\033[0;31m====================================================================\033[0m"; \
		echo -e "\033[0;31m❌[Security Alert] Tailscale VPN Authentication Failed!\033[0m"; \
		echo -e "\033[0;31m   -> Your Tailscale Auth Key (TS_AUTHKEY) has expired (90-day limit) or is invalid.\033[0m"; \
		echo -e ""; \
		echo -e "\033[0;31m[Action Required]\033[0m"; \
		echo -e "\033[0;31m1. Generate a new Auth Key in the Tailscale Admin Console.\033[0m"; \
		echo -e "\033[0;31m2. Update the 'TS_AUTHKEY' secret in your Doppler dashboard.\033[0m"; \
		echo -e "\033[0;31m3. See README.md for detailed instructions.\033[0m"; \
		echo -e "\033[0;31m====================================================================\033[0m"; \
		$(COMPOSE_CMD) down; \
		exit 1; \
	fi
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

# [Update] Host System Security
# [Why] To keep the underlying OS (WSL2) and Docker Engine secure and up-to-date.
update-oss:
	@echo ">>> 🛡️ [Step 1] Updating Host System (apt)..."
	@sudo apt-get update && sudo apt-get upgrade -y
	@echo ">>> 🐳 [Step 2] Cleaning Docker System Garbage..."
	@# Removes stopped containers, unused networks, and dangling images to free disk space
	@docker system prune -f
	@echo "✅ Host system updated and cleaned."

# [Cache] Deep Clean & Rebuild
# [Why] To resolve build-time dependency issues by purging ALL caches.
cache-oss:
	@echo ">>> 🧹 Aggressive Cache Cleanup..."
	@# -a: Remove all unused build cache, not just dangling ones.
	@# -f: Force without prompt.
	@docker builder prune -af
	@docker image prune -f
	
	@echo "✅ Build cache purged. Run 'make build-oss' to rebuild."

# [Clean] Factory Reset
# [Warning] This deletes ALL persistent volumes (Conda envs, models, output).
clean-oss:
	@echo ">>> ☢️ INITIATING FACTORY RESET..."
	@echo "   -> Stopping containers and removing Docker volumes..."
	$(COMPOSE_CMD) down --remove-orphans --volumes
	
	@echo "   -> Sweeping Docker artifacts..."
	@docker rm -f $(CORE_CONTAINERS) 2>/dev/null || true
	
	@echo "   -> Vaporizing Host Data (excluding LLM models)..."
	@sudo rm -rf $(PURGE_DIRS)
	
	@echo "✅ System restored to factory settings."