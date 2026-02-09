"""
Takumi Smart Resolver (Pure Logic Edition)

[Why] "Batch Resolution": Collect ALL requirements -> Merge -> Install once.
"""

import os
import sys
import json
import glob
import subprocess
import re

# --- Config ---
COMFY_ROOT = "/app/external/ComfyUI"
CUSTOM_NODES_DIR = os.path.join(COMFY_ROOT, "custom_nodes")
CACHE_DIR = "/app/cache"
OUTPUT_JSON = os.path.join(CACHE_DIR, "dynamic_requirements.json")

def collect_and_merge():
    """
    Scans all requirements.txt and merges them.
    Returns a dictionary: {pkg_name: version_spec}
    """
    print(f">>> [Resolver] Scanning {CUSTOM_NODES_DIR}...")
    merged_reqs = {}
    
    files = glob.glob(os.path.join(CUSTOM_NODES_DIR, "**/requirements.txt"), recursive=True)
    
    for file_path in files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    # Skip comments/empty
                    if not line or line.startswith("#"): continue
                    
                    # Parse: pkg_name[==version]
                    # Regex handles: package, package==1.0, package>=1.0
                    match = re.match(r'^([a-zA-Z0-9_\-\.]+)(.*)$', line)
                    if match:
                        name = match.group(1).lower()
                        specs = match.group(2)
                        
                        # [Merge Strategy]
                        # If conflict, we overwrite (Last Write Wins) for now.
                        # Ideally, uv handles this if we pass duplicates, but cleaning helps.
                        merged_reqs[name] = specs
        except Exception:
            pass
            
    return merged_reqs

def install_batch(merged_reqs):
    """
    Generates a single installation command for uv.
    """
    if not merged_reqs:
        print(">>> [Resolver] No dependencies found.")
        return True

    # Convert dict to list ["pkg==ver", "pkg2"]
    pkgs = [f"{name}{specs}" for name, specs in merged_reqs.items()]
    
    print(f">>> [Resolver] Batch installing {len(pkgs)} packages...")
    
    # [Performance] Keep concurrency low for stability
    env = os.environ.copy()
    env["UV_CONCURRENT_DOWNLOADS"] = "4"
    env["UV_LINK_MODE"] = "copy"

    # [Fix] Add --system to install into active Conda env
    cmd = ["uv", "pip", "install", "--system"] + pkgs
    
    try:
        # Run uv directly.
        subprocess.run(cmd, check=True, env=env)
        return True
    except subprocess.CalledProcessError:
        print(">>> [Resolver] Installation failed.")
        return False

def main():
    merged = collect_and_merge()
    if install_batch(merged):
        print(">>> [Resolver] ✅ Success.")
        sys.exit(0)
    else:
        print(">>> [Resolver] ❌ Failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()