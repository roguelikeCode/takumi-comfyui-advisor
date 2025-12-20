"""
Takumi Recipe Generator v3.0
[Why] To generate a production-ready JSON recipe from the current environment snapshot.
[What] Scans Git/Pip, auto-generates Metadata & Contribution sections, and dumps structured JSON.
"""

import os
import json
import subprocess
import sys
import datetime

COMFY_PATH = "/app/ComfyUI"
CUSTOM_NODES_PATH = os.path.join(COMFY_PATH, "custom_nodes")

# --- Configuration ---
# Pip packages you want to automatically scan (exclude others as noise or add them manually)
TARGET_PIP_PACKAGES = [
    "torch", "torchvision", "torchaudio", "xformers", "diffusers", 
    "transformers", "accelerate", "insightface", "onnxruntime-gpu", 
    "numpy", "opencv-python", "pillow", "rembg", "matplotlib",
    "scikit-image", "scipy", "tqdm", "einops", "safetensors"
]

def get_git_info(path):
    """[Why] Get the Git repository URL and branch"""
    try:
        url = subprocess.check_output(
            ["git", "-C", path, "remote", "get-url", "origin"],
            encoding="utf-8", stderr=subprocess.DEVNULL
        ).strip()
        if "@" in url: url = "https://" + url.split("@")[-1]
        if url.endswith(".git"): url = url[:-4] # Removed `.git` and unified to use as ID
        
        branch = subprocess.check_output(
            ["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
            encoding="utf-8", stderr=subprocess.DEVNULL
        ).strip()
        return url, branch
    except Exception:
        return None, None

def scan_custom_nodes():
    nodes = []
    if os.path.exists(CUSTOM_NODES_PATH):
        for item in os.listdir(CUSTOM_NODES_PATH):
            item_path = os.path.join(CUSTOM_NODES_PATH, item)
            if os.path.isdir(item_path) and os.path.exists(os.path.join(item_path, ".git")):
                url, branch = get_git_info(item_path)
                if url:
                    nodes.append({
                        "type": "custom-node",
                        "source": url + ".git", # Add `.git`` to source
                        "version": branch,
                        "id": url # Contribution ID
                    })
    return nodes

def scan_pip_packages():
    """[Why] Extract specific packages from pip freeze in the current environment"""
    packages = []
    try:
        result = subprocess.check_output([sys.executable, "-m", "pip", "freeze"], encoding="utf-8")
        for line in result.splitlines():
            if "==" in line:
                name, version = line.split("==")
                if name.lower() in TARGET_PIP_PACKAGES:
                    packages.append({
                        "type": "pip",
                        "source": name,
                        "version": f"=={version}"
                    })
    except Exception:
        pass
    return packages

def generate_contribution(nodes):
    """Auto-generate Contribution section based on custom node URL"""

     # 1. Custom Nodes (Key Technology)
    key_tech_contributors = [{"component_id": node["id"]} for node in nodes]

    # 2. Core Platform & Utilities (Essential Utility)
    essential_contributors = [
        {
            "component_id": "https://github.com/comfyanonymous/ComfyUI",
            "role": "core_platform"
        },
        {
            "component_id": "https://github.com/ltdrdata/ComfyUI-Manager"
        }
    ]
    
    return [
        {
            "type": "use_case_recipe",
            "total_share": 30,
            "distribution_rule": "equal",
            "contributors": [{"id": "did:takumi:user_placeholder"}]
        },
        {
            "type": "key_technology",
            "total_share": 50,
            "distribution_rule": "equal",
            "contributors": key_tech_contributors
        },
        {
            "type": "essential_utility",
            "total_share": 10,
            "distribution_rule": "equal",
            "contributors": essential_contributors
        },
        {
            "type": "platform",
            "total_share": 10,
            "distribution_rule": "equal",
            "contributors": [{"id": "did:takumi:treasury"}]
        }
    ]

def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_recipe.py <use_case_slug>")
        print("Example: python generate_recipe.py create_ai_video")
        return

    slug = sys.argv[1]
    
    print(f"📸 Taking snapshot for: {slug}...")

    # 1. Scan
    custom_nodes = scan_custom_nodes()
    pip_packages = scan_pip_packages()
    
    # 2. Base Components (ComfyUI Body)
    comfy_url, comfy_branch = get_git_info(COMFY_PATH)
    base_components = [{
        "type": "git-clone",
        "source": comfy_url + ".git",
        "version": comfy_branch,
        "path": "/app/ComfyUI"
    }]

    # 3. Merge All Components
    all_components = base_components + custom_nodes + pip_packages

    # 4. Construct JSON
    recipe = {
        "asset_id": f"takumi-use-case-{slug}",
        "asset_version": "1.0.0",
        "display_name": slug.replace("_", " ").title(),
        "description": f"Snapshot generated on {datetime.date.today()}",
        "contribution": generate_contribution(custom_nodes),
        "environment": {
            "name": f"{slug}_env",
            "engine": "conda",
            "components": [
                {"type": "conda", "source": "python", "version": "3.10"},
                {"type": "conda", "source": "pip"},
                {"type": "conda", "source": "pytorch-cuda", "version": "12.1", "channel": "pytorch"},
                {"type": "conda", "source": "ffmpeg", "version": ">=6.0", "channel": "conda-forge"}
            ]
        },
        "components": all_components
    }

    # 5. Output
    output_filename = f"{slug}.json"
    with open(output_filename, "w") as f:
        json.dump(recipe, f, indent=2, ensure_ascii=False)
        f.write('\n')
    
    print(f"✅ Recipe snapshot saved to: {output_filename}")
    print("   -> Review the 'contribution' section and 'pip' versions before release.")

if __name__ == "__main__":
    main()