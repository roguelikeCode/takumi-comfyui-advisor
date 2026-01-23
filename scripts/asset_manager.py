"""
Takumi Asset Manager

[Why] To automate the setup of complex assets (models) and apply code patches.
[What] Reads a recipe JSON, downloads models from Hugging Face, creates symlinks, and patches source code.
"""

import os
import json
import shutil
import sys
from pathlib import Path
from typing import List, Dict, Any
from huggingface_hub import hf_hub_download, login

# [Why] To make the script's behavior configurable from the outside (e.g., shell scripts).
# [Note] Reads the root directory for ComfyUI from an environment variable, with a fallback to the new default.
COMFYUI_ROOT = os.environ.get("COMFYUI_ROOT_DIR", "/app/external/ComfyUI")

# The progress bar disappears when running via Docker or a script, so we force it to be displayed
if not sys.stdout.isatty():
    sys.stdout.isatty = lambda: True
if not sys.stderr.isatty():
    sys.stderr.isatty = lambda: True

# Force progress bar to be displayed (tqdm setting)
os.environ["TQDM_DISABLE"] = "0"

# ==============================================================================
# [1] Configuration
# ==============================================================================
class AssetConfig:
    # Default path inside Docker container
    DEFAULT_RECIPE_PATH = "/app/config/takumi_meta/core/recipes/assets/magic_clothing.json"
    ENV_HF_TOKEN = "HF_TOKEN"

# ==============================================================================
# [2] Utilities & Managers
# ==============================================================================

class AuthManager:
    """Handles authentication with external services."""

    @staticmethod
    def login_huggingface() -> None:
        """
        [Why] To access Gated Models (e.g., SDXL based models) or LFS files.
        [What] Retrieves token from env and authenticates via huggingface_hub.
        """
        token = os.environ.get(AssetConfig.ENV_HF_TOKEN)
        if not token:
            print(f"❌ Error: {AssetConfig.ENV_HF_TOKEN} environment variable is not set.")
            sys.exit(1)
        
        print("🔑 Authenticating with Hugging Face...")
        try:
            login(token=token)
        except Exception as e:
            print(f"❌ Authentication failed: {e}")
            sys.exit(1)

class RecipeLoader:
    """Handles file I/O for recipes."""

    @staticmethod
    def load(path_str: str) -> Dict[str, Any]:
        """
        [Why] To convert the JSON definition into a Python dictionary.
        [Input] path_str: Absolute path to the JSON file.
        [Output] Dict containing the recipe.
        """
        path = Path(path_str)
        if not path.exists():
            print(f"❌ Recipe not found: {path}")
            sys.exit(1)

        try:
            with path.open('r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON format: {e}")
            sys.exit(1)

# ==============================================================================
# [3] Core Processor
# ==============================================================================

class AssetProcessor:
    """Executes the actions defined in the recipe."""

    @staticmethod
    def run_downloads(items: List[Dict[str, str]]) -> None:
        """
        [Why] To fetch required models from the internet.
        [What] Uses huggingface_hub to download files to specified targets.
        """
        print("⬇️ Processing downloads...")
        for item in items:
            if item.get("type") == "huggingface":
                AssetProcessor._download_huggingface(item)

    @staticmethod
    def _resolve_path(path_str: str) -> Path:
        """[Why] To resolve paths relative to the dynamic ComfyUI root."""
        # [What] Replaces the placeholder "/app/ComfyUI" with the actual COMFYUI_ROOT.
        if path_str.startswith("/app/ComfyUI/"):
            return Path(COMFYUI_ROOT) / path_str.replace("/app/ComfyUI/", "", 1)
        return Path(path_str)

    @staticmethod
    def _download_huggingface(item: Dict[str, str]) -> None:
        repo_id = item["repo_id"]
        filename = item["filename"]
        target_dir = AssetProcessor._resolve_path(item["target_dir"])
        
        try:
            print(f"  - Downloading {filename} from {repo_id}...")
            file_path = hf_hub_download(
                repo_id=repo_id,
                filename=filename,
                local_dir=target_dir
            )
            
            # Handle renaming if specified
            if "rename_to" in item:
                source = Path(file_path)
                dest = target_dir / item["rename_to"]
                shutil.move(source, dest)
                print(f"    ✅ Renamed to {item['rename_to']}")
            else:
                print(f"    ✅ Saved to {target_dir}")

        except Exception as e:
            print(f"    ❌ Failed: {e}")
            # Don't exit, try next item

    @staticmethod
    def run_symlinks(items: List[Dict[str, str]]) -> None:
        """
        [Why] To resolve path inconsistencies between different custom nodes.
        [What] Creates symbolic links (shortcuts) to the actual model files.
        """
        print("🔗 Processing symlinks...")
        for item in items:
            src = AssetProcessor._resolve_path(item["src"])
            dest = AssetProcessor._resolve_path(item["dest"])
            
            if not src.exists():
                print(f"    ⚠️ Source not found: {src}")
                continue
                
            # Create parent dir if missing
            dest.parent.mkdir(parents=True, exist_ok=True)
            
            # Remove existing link/file to ensure idempotence
            if dest.exists() or dest.is_symlink():
                dest.unlink()
                
            try:
                dest.symlink_to(src)
                print(f"    ✅ Linked {dest.name} -> {src.name}")
            except OSError as e:
                print(f"    ❌ Link failed: {e}")

    @staticmethod
    def run_patches(items: List[Dict[str, str]]) -> None:
        """
        [Why] To fix bugs or hardcoded paths in third-party code.
        [What] Reads source files, replaces target strings, and overwrites.
        """
        print("🩹 Processing patches...")
        for item in items:
            file_path = AssetProcessor._resolve_path(item["file"])
            find_str = item["find"]
            replace_str = item["replace"]

            if not file_path.exists():
                print(f"    ⚠️ File not found: {file_path}")
                continue
                
            try:
                content = file_path.read_text(encoding="utf-8")
                
                if find_str in content:
                    new_content = content.replace(find_str, replace_str)
                    file_path.write_text(new_content, encoding="utf-8")
                    print(f"    ✅ Patched {file_path.name}")
                elif replace_str in content:
                    print(f"    ℹ️ Already patched: {file_path.name}")
                else:
                    print(f"    ⚠️ Target string not found in {file_path.name}")
                    
            except Exception as e:
                print(f"    ❌ Patch failed: {e}")

# ==============================================================================
# Main Entry Point
# ==============================================================================

def main():
    # Use default recipe if no argument is provided
    recipe_path = sys.argv[1] if len(sys.argv) > 1 else AssetConfig.DEFAULT_RECIPE_PATH
    
    print(f"🚀 Starting Asset Manager")
    
    # 1. Load Recipe
    recipe = RecipeLoader.load(recipe_path)
    print(f"   Target: {recipe.get('id', 'Unknown Recipe')}")

    # 2. Auth
    AuthManager.login_huggingface()
    
    # 3. Execution
    if "downloads" in recipe:
        AssetProcessor.run_downloads(recipe["downloads"])
        
    if "symlinks" in recipe:
        AssetProcessor.run_symlinks(recipe["symlinks"])
        
    if "patches" in recipe:
        AssetProcessor.run_patches(recipe["patches"])

    print("✨ All assets processed successfully.")

if __name__ == "__main__":
    main()