SHELL := /bin/bash

# ==============================================================================
# Takumi OSS Makefile
#
# Theme: "The Studio (Standard)"
# Description: Manages the lifecycle of the Open Source edition (Takumi Advisor).
# ==============================================================================

# --- Configuration ---
DOTENVX_VERSION := v1.52.0
IMAGE_NAME     := takumi-comfyui
IMAGE_TAG      := latest
CONTAINER_NAME := takumi-comfyui-oss

# --- State Files ---
CACHE_DIR            := cache
HISTORY_FILEPATH_OSS := $(CACHE_DIR)/.install_history

# --- Ports ---
WEB_PORT := 8188

# --- Infrastructure ---
REQUIRED_DIRS := cache external logs storage/envs storage/ollama storage/pkgs
PURGE_DIRS    := cache external logs storage

# ==============================================================================
# Docker Options (The Engine)
# ==============================================================================

# --- Security Hardening Options ---
# - no-new-privileges: Prevent sudo usage
# - cap-drop         : Drop root capabilities
# - read-only=false  : Required for some writable temporary paths in Rootless
DOCKER_SEC_OPTS := \
	--security-opt no-new-privileges:true \
	--cap-drop=ALL \
	--cap-add=SYS_NICE \
	--read-only=false

# --- Docker Runtime Options ---
# - Rootless Mode Adaptation
# - HOME=/root
# - /app is Writable (RW) for nested mount creation
# - Storage mapped to /root
# - Scripts mapped as RO (Security)
DOCKER_RUN_OPTS := \
	--rm \
	--gpus all \
	--name $(CONTAINER_NAME) \
	-p $(WEB_PORT):8188 \
	-w /app \
	-e HOME=/root \
	-e HF_TOKEN \
	-e PYTHONDONTWRITEBYTECODE=1 \
	-e CONDA_ENVS_DIRS=/root/.conda/envs \
	-e CONDA_PKGS_DIRS=/root/.conda/pkgs \
	--env-file .env \
	-v $(shell pwd)/app:/app \
	-v $(shell pwd)/scripts:/app/scripts:ro \
	\
	-v $(shell pwd)/cache:/app/cache \
	-v $(shell pwd)/$(HISTORY_FILEPATH_OSS):/app/$(HISTORY_FILEPATH_OSS) \
	-v $(shell pwd)/external:/app/external \
	-v $(shell pwd)/logs:/app/logs \
	-v $(shell pwd)/storage/envs:/root/.conda/envs \
	-v $(shell pwd)/storage/ollama:/root/.ollama \
	-v $(shell pwd)/storage/pkgs:/root/.conda/pkgs

# ==============================================================================
# Command Wrapper
# ==============================================================================
LAUNCHER :=
ifneq (,$(shell command -v dotenvx))
	LAUNCHER := dotenvx run --
endif

# ==============================================================================
# Targets
# ==============================================================================
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Takumi Command Interface:"
	@echo ""
	@echo "  [Setup & Security]"
	@echo "    make setup-env    : Initialize .env and install utilities."
	@echo "    make encrypt      : Encrypt .env file for security."
	@echo ""
	@echo "  [Main]"
	@echo "    make install-oss  : Build and set up the environment (The Magic Command)."
	@echo "    make run-oss      : Start ComfyUI and AI Advisor."
	@echo ""
	@echo "  [Development]"
	@echo "    make build        : Rebuild Docker image."
	@echo "    make shell        : Enter the container shell for debugging."
	@echo "    make test         : Run automated test suite."
	@echo "    make clean-docker : Stop and remove containers."
	@echo "    make clean-env    : Reset environment (Delete envs/caches)."
	@echo "    make clean-all    : Factory reset (Delete everything)."

# ==============================================================================
# 1. Setup & Security
# ==============================================================================
.PHONY: ensure-dirs setup-env encrypt

ensure-dirs:
	@mkdir -p $(REQUIRED_DIRS)
	@touch $(HISTORY_FILEPATH_OSS)

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
# 2. Main (Dockerfile Wrapper)
# ==============================================================================
.PHONY: build install-oss run-oss stop

build: ensure-dirs
	@echo ">>> Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@# Passing Host UID/GID to Dockerfile (Standard Practice, though Rootless handles mapping)
	@docker build \
		--build-arg TAKUMI_UID=$(shell id -u) \
		--build-arg TAKUMI_GID=$(shell id -g) \
		--rm --tag $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "✅ Build complete."

install-oss: build
	@echo ">>> Launching installer..."
	@$(LAUNCHER) docker run \
		$(DOCKER_SEC_OPTS) \
		-it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/install.sh

# [Why] To run the application with optional secret decryption.
# [What] Dynamically prepends 'dotenvx run --' if the tool is available.
run-oss: build
	@echo ">>> Starting ComfyUI..."
	@echo ">>> Open http://localhost:$(WEB_PORT) for ComfyUI"
	@$(LAUNCHER) docker run \
		$(DOCKER_SEC_OPTS) \
		-it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run.sh

stop:
	@echo ">>> Stopping container..."
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true

# ==============================================================================
# 3. Utilities & Cleanup
# ==============================================================================
.PHONY: shell test clean-docker clean-env clean-all

shell: build
	@echo ">>> Starting interactive shell..."
	@$(LAUNCHER) docker run \
		$(DOCKER_SEC_OPTS) \
		-it $(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash

test: build
	@echo ">>> Running tests..."
	@$(LAUNCHER) docker run \
		$(DOCKER_SEC_OPTS) \
		$(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run_tests.sh

# [Level 1] Clean Docker Containers
clean-docker:
	@echo ">>> 🧹 Removing container artifacts..."
	@-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@-docker rmi -f $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "✅ Cleanup complete."

# [Level 2] Clean Environment & Cache
clean-env: clean-docker
	@echo ">>> ☢️  Cleaning Runtime Environments (OSS)..."
	@# Use sudo just in case, but finding/deleting content only
	@if [ -d "storage" ]; then \
		echo "   -> Removing caches and environments..."; \
		sudo rm -rf $(PURGE_DIRS); \
	fi
	@make ensure-dirs
	@echo "✅ Environment reset. Please run 'make install-oss' again."

# [Level 3] Factory Reset
clean-all: clean-env
	@echo ">>> ☢️  INITIATING FACTORY RESET..."
	@echo "   -> Wiping all ComfyUI data..."
	@if [ -d "external/ComfyUI" ]; then \
		sudo rm -rf external/ComfyUI; \
	fi
	@echo "✅ System restored to factory settings."