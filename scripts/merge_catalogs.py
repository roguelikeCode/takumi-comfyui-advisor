"""
Takumi Catalog Merger
[Why] Merging the 'Core' and 'Enterprise' JSON catalogs.
[What] Read multiple JSON files, merge them (last one wins) and output them as a dictionary.
[Input] args: output_path, input_path1, input_path2, ...
"""
import sys
import json
import os

def merge_dicts(base, overlay):
    """Simple merge (overwrite) on a top-level key basis, not recursively"""
    # For Takumi's metadata structure (ID is the key), update() is sufficient.
    base.update(overlay)
    return base

def main():
    if len(sys.argv) < 3:
        print("Usage: python merge_catalogs.py <output_path> <input1> [input2 ...]", file=sys.stderr)
        sys.exit(1)

    output_path = sys.argv[1]
    input_paths = sys.argv[2:]

    merged_data = {}

    # It is necessary to determine whether the catalog is an external catalog (ComfyUI-Manager format) or Takumi format,
    # The basic strategy is to merge them as a "dictionary keyed by ID."
    # However, since ComfyUI-Manager lists can be arrays, normalization is required.

    for path in input_paths:
        if not os.path.exists(path):
            continue
            
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
                # If it is an array, convert it to an ID map (normalization)
                if isinstance(data, list):
                    # ComfyUI-Manager Custom Node List
                    temp_map = {}
                    for item in data:
                        # Use URL etc. as a key
                        key = item.get("reference") or item.get("url")
                        if key:
                            temp_map[key] = item
                    data = temp_map
                
                # If there is a 'custom_nodes' key (Takumi Meta format)
                if "custom_nodes" in data:
                    data = data["custom_nodes"]

                # Merge
                merged_data.update(data)
                
        except Exception as e:
            print(f"Warning: Failed to merge {path}: {e}", file=sys.stderr)

    # Output
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(merged_data, f, indent=2, ensure_ascii=False)

    print(f"Successfully merged {len(input_paths)} catalogs into {output_path}")

if __name__ == "__main__":
    main()