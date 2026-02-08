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
	@echo ">>> [Step 1] Waking up Infrastructure..."
	$(COMPOSE_CMD) up -d --wait
	@echo ">>> [Step 2] Running Installer..."
	$(COMPOSE_CMD) exec comfyui bash /app/install.sh
	@echo ">>> [Step 3] Restarting Runtime (Apply Changes)..."
	$(COMPOSE_CMD) restart comfyui
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

# [Clean] Factory Reset
# [Warning] This deletes ALL persistent volumes (Conda envs, models, output).
clean-oss:
	@echo ">>> ☢️  INITIATING FACTORY RESET..."
	@echo "   -> Stopping containers..."
	$(COMPOSE_CMD) down --remove-orphans --volumes
	@echo "   -> Sweeping artifacts..."
	@docker rm -f takumi-comfyui-oss takumi-ollama 2>/dev/null || true
	@echo "✅ System restored to factory settings."