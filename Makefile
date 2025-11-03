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
.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build         Build the Docker image for the development environment."
	@echo "  help          Show this help message."
	@echo ""
	@echo "Example:"
	@echo "  make build"

.DEFAULT_GOAL := help

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

# --- Variables (Main Execution Engine) ---
MANAGER_LIST_URL := https://raw.githubusercontent.com/Comfy-Org/ComfyUI-Manager/main/custom-node-list.json
CACHE_DIR := ./cache
CUSTOM_NODE_LIST_CACHE := $(CACHE_DIR)/custom-node-list.json

# --- Variables (Dockerfile Wrapper) ---
IMAGE_NAME := takumi-comfyui
IMAGE_TAG  := latest
CONTAINER_NAME := takumi-comfyui-dev

# ==============================================================================
# Main Execution Engine Recipes
# ==============================================================================

# --- Core Atomic Recipes ---
# These are the individual, single-purpose building blocks.

.PHONY: dev-install update-node-list install-loop
dev-install: build
	@echo ">>> Launching installer in DEV MODE (logs will be saved locally)..."
    docker run -it --rm \
        -e TAKUMI_DEV_MODE=true \ # <-- 環境変数を設定
        -v $(shell pwd)/logs:/app/logs \ # <-- ローカルのlogsフォルダをマウント
        takumi-comfyui \
        bash /app/install.sh

update-node-list:
	@mkdir -p $(CACHE_DIR)
	@echo ">>> Downloading latest custom node list from ComfyUI-Manager..."
	@wget -O $(CUSTOM_NODE_LIST_CACHE) $(MANAGER_LIST_URL)
	@echo "✅ Node list updated successfully."

install-loop:
	@attempt_history_file=".install_history"; \
	touch $$attempt_history_file; \
	while true; do \
		echo "--- Starting new installation attempt ---"; \
		docker run -it --rm \
			--gpus all \
			-v ./comfyui_models:/app/ComfyUI/models \
			-v $(shell pwd)/$$attempt_history_file:/app/.install_history \
			takumi-comfyui \
			bash /app/install.sh; \
		
		exit_code=$$?; \
		if [ $$exit_code -eq 0 ]; then \
			echo "✅ Installation successful!"; \
			rm -f $$attempt_history_file; \
			break; \
		elif [ $$exit_code -eq 125 ]; then \
			# install.shが「takumiに報告」を選択して終了した場合の特殊コード
			echo "🛑 Reporting to Takumi..."; \
			rm -f $$attempt_history_file; \
			break; \
		else \
			read -p "Installation failed. Retry with a different strategy? (Y/n): " consent; \
			if [[ "$$consent" == "n" || "$$consent" == "N" ]]; then \
				echo "Aborted by user."; \
				rm -f $$attempt_history_file; \
				break; \
			fi; \
		fi; \
	done

# `install`レシピは、このループを呼び出すだけ
.PHONY: install
install: update-node-list build
	$(MAKE) install-loop

# ==============================================================================
# Dockerfile Wrapper Recipes
# ==============================================================================

# --- Core Atomic Recipes ---
# These are the individual, single-purpose building blocks.
.PHONY: build
build:
	@echo "Building Docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	docker build \
		--rm \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		.
	@echo "Build complete. Image '$(IMAGE_NAME):$(IMAGE_TAG)' is ready."

# ... (docker run -it ... のコマンド)