import json
import sys
import os

def load_json(path):
    # 1. Load if the path exists (Absolute Path Success)
    if os.path.exists(path):
        return json.load(open(path, 'r'))

    # 2. Path normalization (Normalization)
    # If the old absolute path ("/app/config/takumi_meta/recipes/...") was specified,
    # Remove the prefix and convert to a relative path ("foundation/...")
    legacy_prefix = "/app/config/takumi_meta/recipes/"
    if path.startswith(legacy_prefix):
        path = path.replace(legacy_prefix, "")
    
    # Remove the leading / (due to os.path.join)
    relative_path = path.lstrip("/")

    # 3. Namespace Lookup (Search Path: Enterprise -> Core)
    base_dir = "/app/config/takumi_meta"
    namespaces = ["enterprise", "core"]
    
    for ns in namespaces:
        # Candidate Path: /app/config/takumi_meta/{ns}/recipes/{relative_path}
        candidate = os.path.join(base_dir, ns, "recipes", relative_path)
        if os.path.exists(candidate):
            print(f"  -> Found dependency in [{ns}]: {relative_path}", file=sys.stderr)
            return json.load(open(candidate, 'r'))

    # 4. Give Up
    print(f"Error: Recipe file not found: {path}", file=sys.stderr)
    print(f"       (Searched in: {namespaces})", file=sys.stderr)
    sys.exit(1)

def merge_components(base_comps, main_comps):
    """Component merging (Main takes precedence)"""
    merged_map = {}
    for c in base_comps:
        key = f"{c['type']}:{c.get('source', 'unknown')}"
        merged_map[key] = c
    for c in main_comps:
        key = f"{c['type']}:{c.get('source', 'unknown')}"
        merged_map[key] = c
    return list(merged_map.values())

def main():
    if len(sys.argv) < 2:
        print("Usage: python merge_recipes.py <main_recipe_path>", file=sys.stderr)
        sys.exit(1)

    main_path = sys.argv[1]
    # Loading the main recipe
    main_data = load_json(main_path)

    # Base Recipe Integration
    base_path = main_data.get("base_recipe")
    if base_path:
        base_data = load_json(base_path)
        
        main_data["components"] = merge_components(
            base_data.get("components", []),
            main_data.get("components", [])
        )
        if "environment" not in main_data and "environment" in base_data:
            main_data["environment"] = base_data["environment"]

    print(json.dumps(main_data, indent=2))

if __name__ == "__main__":
    main()