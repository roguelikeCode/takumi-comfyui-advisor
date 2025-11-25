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
# [追加] Condaの仮想環境をホスト側の 'storage/envs' に保存する
# これにより、コンテナを再起動しても環境が維持される
DOCKER_RUN_OPTS := --rm \
	--name $(CONTAINER_NAME) \
	--user $(shell id -u):$(shell id -g) \
	-w /app \
	-e HOME=/home/takumi \
	-v $(shell pwd)/cache:/app/cache \
	-v $(shell pwd)/logs:/app/logs \
	-v $(shell pwd)/external:/app/external \
	-v $(shell pwd)/app:/app \
	-v $(shell pwd)/scripts:/app/scripts \
	-v $(shell pwd)/storage/envs:/home/takumi/.conda/envs 

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
	@docker build \
		--build-arg TAKUMI_UID=$(shell id -u) \
		--build-arg TAKUMI_GID=$(shell id -g) \
		--rm --tag $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "✅ Build complete."

install: build
	@echo ">>> Launching installer wrapper..."
	@bash ./scripts/run_installer.sh

run:
	@echo ">>> Starting ComfyUI..."
	@echo ">>> Open http://localhost:8188 in your browser after server starts."
	@docker run -it --rm \
		--gpus all \
		-p 8188:8188 \
		$(DOCKER_RUN_OPTS) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		bash /app/scripts/run.sh

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