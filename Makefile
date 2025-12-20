# ==============================================================================
# Takumi-ComfyUI Makefile
#
# Maintainer: Yamato Watase
# Description: This Makefile is the high-level orchestrator for the project.
#              It wraps complex, fragmented node commands with simple, memorable targets
#              for developers.
# ==============================================================================
SHELL := /bin/bash

# ==============================================================================
# Configuration
# ==============================================================================
# --- Versions ---
DOTENVX_VERSION := v1.51.1

# --- Container Settings ---
IMAGE_NAME      := takumi-comfyui
IMAGE_TAG       := latest
CONTAINER_NAME  := takumi-comfyui-dev

# --- Ports ---
WEB_PORT        := 8188

# --- Docker Runtime Options (Encapsulation) ---
# [Why] Defined as a multiline variable for readability and easier maintenance.
# [What] Maps host directories to the container and sets user permissions.
DOCKER_RUN_OPTS := \
	--rm \
	--gpus all \
	--name $(CONTAINER_NAME) \
	--user $(shell id -u):$(shell id -g) \
	-p $(WEB_PORT):8188 \
	-w /app \
	-e HOME=/home/takumi \
	-e HF_TOKEN \
	--env-file .env \
	-v $(shell pwd)/cache:/app/cache \
	-v $(shell pwd)/logs:/app/logs \
	-v $(shell pwd)/external:/app/external \
	-v $(shell pwd)/app:/app \
	-v $(shell pwd)/scripts:/app/scripts \
	-v $(shell pwd)/storage/pkgs:/home/takumi/.conda/pkgs \
	-v $(shell pwd)/storage/envs:/home/takumi/.conda/envs \
	-v $(shell pwd)/storage/ollama:/home/takumi/.ollama \
	-v $(shell pwd)/.install_history:/app/.install_history

# --- Pre-flight Checks ---
REQUIRED_DIRS := logs cache external config storage/pkgs storage/envs storage/ollama

# ==============================================================================
# Targets
# ==============================================================================
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Takumi Command Interface:"
	@echo ""
	@echo "  [Setup & Security]"
	@echo "    make setup-env   : Initialize .env and install utilities."
	@echo "    make encrypt     : Encrypt .env file for security."
	@echo ""
	@echo "  [Main]"
	@echo "    make install     : Build and set up the environment (The Magic Command)."
	@echo "    make run         : Start ComfyUI and AI Advisor."
	@echo ""
	@echo "  [Development]"
	@echo "    make build       : Rebuild Docker image manually."
	@echo "    make shell       : Enter the container shell for debugging."
	@echo "    make test        : Run automated test suite."
	@echo "    make clean       : Remove all artifacts and images."
	@echo "    make purge       : [DANGER] Delete ALL data and reset to factory settings."

# ==============================================================================
# 1. Setup & Security
# ==============================================================================
.PHONY: setup-env encrypt
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
# 2. Main (Dockerfile Wrapper Recipes)
# ==============================================================================
.PHONY: ensure-dirs build install run
ensure-dirs:
	@mkdir -p $(REQUIRED_DIRS)

build: ensure-dirs
	@echo ">>> Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker build \
		--build-arg TAKUMI_UID=$(shell id -u) \
		--build-arg TAKUMI_GID=$(shell id -g) \
		--rm --tag $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "✅ Build complete."

install: build
	@echo ">>> Launching installer wrapper..."
	@bash ./scripts/run_installer.sh

# [Why] To run the application with optional secret decryption.
# [What] Dynamically prepends 'dotenvx run --' if the tool is available.
# [Note] Ensure that the `.install_history` file is created before executing the run target
run: build
	@echo ">>> Starting ComfyUI..."
	@echo ">>> Open http://localhost:$(WEB_PORT) for ComfyUI"
	@touch .install_history
	@LAUNCHER=""; \
	if command -v dotenvx >/dev/null 2>&1; then \
		LAUNCHER="dotenvx run --"; \
	fi; \
	$$LAUNCHER docker run -it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run.sh

# ==============================================================================
# 3. Development Utilities
# ==============================================================================
.PHONY: shell test clean purge
#[Note] If there is no .install_history file, Docker will create the directory
shell: build
	@echo ">>> Starting interactive shell..."
	@touch .install_history
	@docker run -it $(DOCKER_RUN_OPTS) $(IMAGE_NAME):$(IMAGE_TAG) bash

#[Note] If there is no .install_history file, Docker will create the directory
test: build
	@echo ">>> Running tests..."
	@touch .install_history
	@docker run $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run_tests.sh

clean:
	@echo ">>> Cleaning up..."
	@-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@-docker rmi -f $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@-rm -rf ./cache/* ./logs/* ./external/* ./app/ComfyUI
	@echo "✅ Cleanup complete."

# [Why] Nuclear option. Wipes EVERYTHING including persistent storage (Conda envs, Models).
# [Note] Use this when you want to start from absolute zero.
# [Note] This will cause the download time to increase.
purge:
	@echo ">>> ☢️  INITIATING TOTAL PURGE... ☢️"
	@echo ">>> This will delete ALL environments, downloaded models, and caches."
	@echo ">>> Use sudo to delete the root privilege files created by Docker."

	@sudo rm -rf \
		app/ComfyUI \
		external \
		cache \
		logs \
		storage \
		.install_history \
		app/.active_env
	
	@mkdir -p logs cache external storage/pkgs storage/envs storage/ollama
	
	@echo "✅ Project has been reset to factory settings."