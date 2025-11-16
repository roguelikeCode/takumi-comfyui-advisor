# ==============================================================================
# Takumi-ComfyUI Makefile
#
# Maintainer: Yamato Watase
# Description: This Makefile is the high-level orchestrator for the project.
#              It wraps complex, fragmented node commands with simple, memorable targets
#              for developers.
# ==============================================================================
SHELL := /bin/bash

# --- Help Message (Default Target) ---
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Lifecycle Commands:"
	@echo "  build         Build the Docker image from Dockerfile."
	@echo "  install       Run the guided installation process inside a new container."
	@echo "  run           Run the main application (e.g., ComfyUI) in a container."
	@echo ""
	@echo "Development Commands:"
	@echo "  shell         Start an interactive shell inside a new container for debugging."
	@echo "  test          Run automated tests to verify the environment and scripts."
	@echo "  clean         Remove built images and cached files."

# ==============================================================================
# Shell Color Codes
# ==============================================================================
YELLOW := \033[1;33m # Bold
RED    := \033[0;31m
GREEN  := \033[0;32m
BLUE   := \033[1;36m # Light Blue/Cyan for info
RESET  := \033[0m

# ==============================================================================
# Configuration
# ==============================================================================
# --- Variables ---
MANAGER_LIST_URL := https://raw.githubusercontent.com/Comfy-Org/ComfyUI-Manager/main/custom-node-list.json
CACHE_DIR := ./cache
CUSTOM_NODE_LIST_CACHE := $(CACHE_DIR)/custom-node-list.json

# --- Variables (Dockerfile Wrapper) ---
IMAGE_NAME := takumi-comfyui
IMAGE_TAG  := latest
CONTAINER_NAME := takumi-comfyui-dev
DOCKER_RUN_OPTS := --rm \
	--name $(CONTAINER_NAME) \
	--user $(shell id -u):$(shell id -g) \
	-v /etc/passwd:/etc/passwd:ro \
	-v /etc/group:/etc/group:ro \
	-v $(shell pwd)/cache:/app/cache \
	-v $(shell pwd)/logs:/app/logs \
	-v $(shell pwd)/external:/app/external

# ==============================================================================
# Dockerfile Wrapper Recipes
# ==============================================================================
.PHONY: main dev maintenance
main:
dev:
maintenance:

# --- Main ---
.PHONY: build install run
build:
	@echo ">>> Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker build --rm --tag $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "✅ Build complete."

install: build
	@echo ">>> Launching installer wrapper..."
	@bash ./scripts/run_installer.sh

# [未実装] 将来、ComfyUIを起動するコマンドをここに記述する
run: build
	@echo ">>> Running the application..."
	@echo "WARN: 'run' target is not yet implemented."
# 例: docker run -it -p 8188:8188 $(DOCKER_RUN_OPTS) --gpus all $(IMAGE_NAME):$(IMAGE_TAG) python main.py

# --- Development ---
.PHONY: shell test lint
shell: build
	@echo ">>> Starting interactive shell in a new container (with GPU access)..."
	@echo "    - Type 'exit' or press Ctrl+D to leave."
	@echo "    - Your current directory is mounted at /app."
	@docker run -it --gpus all $(DOCKER_RUN_OPTS) $(IMAGE_NAME):$(IMAGE_TAG) bash

test: build
	@echo ">>> Running tests inside a new container..."
	@docker run $(DOCKER_RUN_OPTS) \
		-v $(shell pwd)/scripts/run-tests.sh:/app/tests/run.sh \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/tests/run.sh

lint: 

# --- Maintenance ---
.PHONY: clean
clean:
	@echo ">>> Cleaning up..."
	@-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@-docker rmi -f $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@-rm -rf ./cache/* ./logs/*
	@echo "✅ Cleanup complete."