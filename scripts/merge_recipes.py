import json
import sys
import os
import re

# [Why] Dependency-free parser to avoid installing pyyaml before conda setup.
def parse_simple_yaml_deps(yaml_path):
    """
    Parses a simple Conda environment.yml file.
    Returns: A list of dicts suitable for Takumi JSON 'components'.
    """
    comps = []
    env_name = "custom_env"
    channels = []
    
    with open(yaml_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    section = None # 'dependencies' or 'channels'
    
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"): continue
        
        # Section Detection
        if line.startswith("name:"):
            env_name = line.split(":", 1)[1].strip()
            section = None
        elif line.startswith("channels:"):
            section = "channels"
        elif line.startswith("dependencies:"):
            section = "dependencies"
            
        # List Parsing
        elif line.startswith("-"):
            value = line.lstrip("- ").strip()
            
            if section == "channels":
                channels.append(value)

            elif section == "dependencies":
                # Skip special pip sections
                if isinstance(value, dict) or value == "pip:": continue
                
                # Parse: "package=version" or "package>=version"
                # Allowed chars: a-z, A-Z, 0-9, _, -, .
                match = re.match(r'^([a-zA-Z0-9_\-\.]+)(?:([<>=]+)(.+))?$', value)
                if match:
                    comps.append({
                        "type": "conda",
                        "source": match.group(1),
                        "version": (match.group(2) or "") + (match.group(3) or "")
                    })
    
    return env_name, comps, channels

def load_json(path):
    # Try direct path
    if os.path.exists(path):
        return json.load(open(path, 'r'))

    # Try searching in namespaces
    relative_path = path.split("recipes/")[-1] # Extract relative path if needed
    base_dir = "/app/config/takumi_meta"
    namespaces = ["enterprise", "core"]
    
    for ns in namespaces:
        # Candidate Path: /app/config/takumi_meta/{ns}/recipes/{relative_path}
        candidate = os.path.join(base_dir, ns, "recipes", relative_path)
        if os.path.exists(candidate):
            print(f"  -> Found dependency in [{ns}]: {relative_path}", file=sys.stderr)
            return json.load(open(candidate, 'r'))

    # Give Up
    print(f"Error: Recipe file not found: {path}", file=sys.stderr)
    sys.exit(1)

def merge_components(base_comps, main_comps):
    """Merge components list, preferring main_comps items by source key."""
    merged_map = {}
    for c in base_comps + main_comps:
        key = f"{c['type']}:{c.get('source', 'unknown')}"
        merged_map[key] = c
    return list(merged_map.values())

def main():
    # Args: 1=recipe_path, 2=env_id (Optional)
    if len(sys.argv) < 2:
        print("Usage: python merge_recipes.py <recipe_path> [env_id]", file=sys.stderr)
        sys.exit(1)

    recipe_path = sys.argv[1]
    env_id = sys.argv[2] if len(sys.argv) > 2 else None

    # Loading the main recipe
    main_data = load_json(recipe_path)

    # [1] Dynamic Environment Injection
    if env_id:
        yaml_rel = f"infra/environments/{env_id}.yml"
        yaml_path = None
        
        # Find YAML in namespaces
        for ns in ["enterprise", "core"]:
            candidate = os.path.join("/app/config/takumi_meta", ns, yaml_rel)
            if os.path.exists(candidate):
                yaml_path = candidate
                break
        
        if yaml_path:
            yaml_name, yaml_comps, yaml_channels = parse_simple_yaml_deps(yaml_path)
            
            # Prefer JSON name if exists, else use YAML name
            target_name = main_data.get("environment", {}).get("name", yaml_name)
            
            main_data["environment"] = {
                "name": target_name,
                "engine": "conda",
                "channels": yaml_channels,
                "components": yaml_comps
            }

    # [2] Base Recipe Merge
    if "base_recipe" in main_data:
        base_data = load_json(main_data["base_recipe"])
        
        main_data["components"] = merge_components(
            base_data.get("components", []),
            main_data.get("components", [])
        )
        # Fallback environment if not injected
        if "environment" not in main_data and "environment" in base_data:
            main_data["environment"] = base_data["environment"]

    print(json.dumps(main_data, indent=2))

if __name__ == "__main__":
    main()