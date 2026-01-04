import json
import sys
import os

def load_json(path):
    # コンテナ内のパスとして解決
    if not os.path.exists(path):
        # 相対パスの場合は /app/config/takumi_meta/recipes/ から探すフォールバック
        alt_path = os.path.join("/app/config/takumi_meta/recipes", path.lstrip("/"))
        if os.path.exists(alt_path):
            return json.load(open(alt_path, 'r'))
        print(f"Error: Recipe file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return json.load(open(path, 'r'))

def merge_components(base_comps, main_comps):
    """
    コンポーネントをマージする。
    'source' をキーにして、Main側の定義でBase側を上書きする。
    """
    merged_map = {}
    
    # Baseを登録
    for c in base_comps:
        key = f"{c['type']}:{c.get('source', 'unknown')}"
        merged_map[key] = c
        
    # Mainで上書き
    for c in main_comps:
        key = f"{c['type']}:{c.get('source', 'unknown')}"
        merged_map[key] = c # Overwrite
        
    return list(merged_map.values())

def main():
    if len(sys.argv) < 2:
        print("Usage: python merge_recipes.py <main_recipe_path>", file=sys.stderr)
        sys.exit(1)

    main_path = sys.argv[1]
    print(f"Loading main recipe: {main_path}", file=sys.stderr)
    main_data = load_json(main_path)

    # Base Recipeの確認
    base_path = main_data.get("base_recipe")
    if base_path:
        print(f"Loading base recipe: {base_path}", file=sys.stderr)
        base_data = load_json(base_path)
        
        # Merge Components
        main_data["components"] = merge_components(
            base_data.get("components", []),
            main_data.get("components", [])
        )
        # EnvironmentはMainを優先（マージしない、単純上書き）
        if "environment" not in main_data and "environment" in base_data:
            main_data["environment"] = base_data["environment"]

    # マージ結果を標準出力へ (JSON)
    print(json.dumps(main_data, indent=2))

if __name__ == "__main__":
    main()