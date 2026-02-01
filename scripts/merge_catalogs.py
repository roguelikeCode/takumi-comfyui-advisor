"""
Takumi Catalog Merger
[Why] Merging the 'Core' and 'Enterprise' JSON catalogs.
[What] Read multiple JSON files, merge them (last one wins) and output them as a dictionary.
[Input] args: output_path, input_path1, input_path2, ...
"""
import sys
import json
import os

def normalize_to_dict(data):
    """
    Normalizes input data (List or Dict) into a Dict keyed by ID/URL.
    """
    normalized = {}
    
    # Input is a List (e.g., ComfyUI-Manager format)
    if isinstance(data, list):
        for item in data:
            key = item.get("reference") or item.get("url") or item.get("git_url")
            if key:
                if key.endswith(".git"): key = key[:-4]
                normalized[key] = item
        return normalized

    # Input is a Dict
    if isinstance(data, dict):
        # Takumi Meta Format (wrapped in 'custom_nodes')
        if "custom_nodes" in data:
            content = data["custom_nodes"]
            if isinstance(content, list):
                return normalize_to_dict(content) # Recursive normalization
            return content
        
        # Simple ID-Value Map
        return data

    return {}

def main():
    if len(sys.argv) < 3:
        print("Usage: python merge_catalogs.py <output_path> <input1> [input2 ...]", file=sys.stderr)
        sys.exit(1)

    output_path = sys.argv[1]
    input_paths = sys.argv[2:]
    merged_data = {}

    for path in input_paths:
        if not os.path.exists(path): continue
            
        try:
            with open(path, 'r', encoding='utf-8') as f:
                raw_data = json.load(f)
                
            clean_data = normalize_to_dict(raw_data)
            if clean_data:
                merged_data.update(clean_data)
            else:
                print(f"Warning: Could not parse {path}, skipping.", file=sys.stderr)
                
        except Exception as e:
            print(f"Warning: Failed to merge {path}: {e}", file=sys.stderr)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(merged_data, f, indent=2, ensure_ascii=False)

    print(f"Successfully merged catalogs into {output_path}")

if __name__ == "__main__":
    main()