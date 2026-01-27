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
IMAGE_NAME     := takumi-comfyui
IMAGE_TAG      := latest
CONTAINER_NAME := takumi-comfyui-oss

# --- State Files ---
CACHE_DIR            := cache
HISTORY_FILEPATH_OSS := $(CACHE_DIR)/.install_history

# --- Ports ---
WEB_PORT := 8188

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
	-e PYTHONDONTWRITEBYTECODE=1 \
	--env-file .env \
	-v $(shell pwd)/app:/app:ro \
	-v $(shell pwd)/scripts:/app/scripts:ro \
	\
	-v $(shell pwd)/cache:/app/cache \
	-v $(shell pwd)/$(HISTORY_FILEPATH_OSS):/app/$(HISTORY_FILEPATH_OSS) \
	-v $(shell pwd)/external:/app/external \
	-v $(shell pwd)/logs:/app/logs \
	-v $(shell pwd)/storage/envs:/home/takumi/.conda/envs \
	-v $(shell pwd)/storage/ollama:/home/takumi/.ollama \
	-v $(shell pwd)/storage/pkgs:/home/takumi/.conda/pkgs

# --- Security Hardening ---
# [Why] Prevent privilege escalation and drop unnecessary capabilities
DOCKER_SEC_OPTS := \
	--security-opt no-new-privileges:true \
	--cap-drop=ALL \
	--cap-add=SYS_NICE \
	--read-only=false

# --- Pre-flight Checks ---
REQUIRED_DIRS := cache external logs storage/envs storage/ollama storage/pkgs
PURGE_DIRS    := cache external logs storage

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
# 1. Security & Setup
# ==============================================================================
.PHONY: setup-env encrypt ensure-dirs
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

ensure-dirs:
	@mkdir -p $(REQUIRED_DIRS)
	@touch $(HISTORY_FILEPATH_OSS)

# ==============================================================================
# 2. Main (Dockerfile Wrapper Recipes)
# ==============================================================================
.PHONY: build install run
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
run: build
	@echo ">>> Starting ComfyUI..."
	@echo ">>> Open http://localhost:$(WEB_PORT) for ComfyUI"
	@LAUNCHER=""; \
	if command -v dotenvx >/dev/null 2>&1; then \
		LAUNCHER="dotenvx run --"; \
	fi; \
	$$LAUNCHER docker run \
		$(DOCKER_SEC_OPTS) \
		-it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run.sh

# ==============================================================================
# 3. Development Utilities
# ==============================================================================
.PHONY: shell test clean purge
shell: build
	@echo ">>> Starting interactive shell..."
	@docker run \
		-it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash

test: build
	@echo ">>> Running tests..."
	@docker run \
		--cap-drop=ALL \
		$(DOCKER_RUN_OPTS) \
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
purge: clean
	@echo ">>> ☢️  INITIATING TOTAL PURGE... ☢️"
	@echo ">>> This will delete ALL environments, downloaded models, and caches."
	@echo ">>> Use sudo to delete the root privilege files created by Docker."

	@sudo rm -rf $(PURGE_DIRS)
	@make ensure-dirs
	
	@echo "✅ Project has been reset to factory settings."

# [Note] The "Scorched Earth" Strategy
nuke: purge
	@echo ">>> ☢️  INITIATING NUCLEAR LAUNCH DETECTED... ☢️"
	@echo ">>> 🧹 Wiping all Custom Nodes (Ghosts)..."
	
	@# OSS version does not require 'core/' prefix
	@if [ -d "external/ComfyUI/custom_nodes" ]; then \
		sudo rm -rf external/ComfyUI/custom_nodes/*; \
		echo "   -> Custom Nodes vaporized."; \
	fi
	
	@echo "✅ Ground Zero established. Ready for fresh install."