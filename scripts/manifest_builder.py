import tomllib  # Python 3.11+ 標準ライブラリ (3.10以下なら `tomli` を使用)
import json
import yaml     # PyYAML (`pip install pyyaml`)
import sys
import os

# --- 設定 ---
PYPROJECT_PATH = "pyproject.toml" # 実際のパスに合わせて調整
CATALOG_PATH = "cache/catalogs/custom_nodes_merged.json"
OUTPUT_PATH = "app/config/recipes/use_cases/generated_manifest.yml"

def load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)

def load_json(path):
    with open(path, "r") as f:
        return json.load(f)

def parse_poetry_dependencies(toml_data):
    """pyproject.tomlの依存関係をGraphAIスタイルのリストに変換する"""
    components = []
    
    # tool.poetry.dependencies または tool.poetry.group.x.dependencies を参照
    # ここでは例としてメインの dependencies を取得
    deps = toml_data.get("tool", {}).get("poetry", {}).get("dependencies", {})
    
    for pkg_name, version_spec in deps.items():
        if pkg_name == "python": continue # python自体のバージョンはcondaで管理するため除外

        # Poetryのバージョン指定 (e.g., "^1.0") を pip形式 (e.g., ">=1.0,<2.0") に変換するロジックが
        # 本来は必要だが、ここでは簡易的にそのまま渡すか、"=="に固定する等の処理を行う。
        # 今回は文字列としてそのまま渡す。
        
        component = {
            "type": "pip",
            "source": pkg_name,
            "version": str(version_spec) # 必要に応じて整形
        }
        components.append(component)
        
    return components

def main():
    print(f">>> Loading data from {PYPROJECT_PATH}...")
    
    try:
        toml_data = load_toml(PYPROJECT_PATH)
        # catalog = load_json(CATALOG_PATH) # バリデーションに使うなら読み込む
    except FileNotFoundError as e:
        print(f"Error: {e}")
        return

    # 1. Pipコンポーネントの生成
    pip_components = parse_poetry_dependencies(toml_data)
    
    # 2. Custom Nodeコンポーネント (これはpyproject.tomlにはないので、
    #    別の定義ファイルから読むか、スクリプト内で定義するか、あるいは
    #    tomlの [tool.takumi.custom_nodes] セクションから読む)
    custom_node_components = []
    
    # (例) TOMLにカスタムセクションを作ってそこから読む場合
    takumi_nodes = toml_data.get("tool", {}).get("takumi", {}).get("nodes", [])
    for node_id in takumi_nodes:
        custom_node_components.append({
            "type": "custom-node",
            "source": node_id, # IDのみ記述。URL解決はinstall.shが行う
            "version": "main"
        })

    # 3. 結合
    full_components = custom_node_components + pip_components

    # 4. ベースとなるYAML構造（メタデータなど）
    manifest = {
        "asset_id": "generated-asset-001",
        "display_name": "Auto Generated Recipe",
        "environment": {
            "name": "auto-env",
            "engine": "conda",
            "components": [
                {"type": "conda", "source": "python", "version": "3.10"},
                {"type": "conda", "source": "pip"},
                {"type": "conda", "source": "pytorch-cuda", "version": "11.8", "channel": "pytorch"}
            ]
        },
        "components": full_components
    }

    # 5. YAML出力
    print(f">>> Generating manifest to {OUTPUT_PATH}...")
    
    # カスタムDumper設定（見やすくするため）
    class IndentDumper(yaml.Dumper):
        def increase_indent(self, flow=False, indentless=False):
            return super(IndentDumper, self).increase_indent(flow, False)

    with open(OUTPUT_PATH, "w") as f:
        # ヘッダーコメント等は手動で書くか、テンプレートエンジンを使うと良い
        f.write("# ===================================================\n")
        f.write("# Asset Manifest (Auto Generated)\n")
        f.write("# ===================================================\n\n")
        yaml.dump(manifest, f, Dumper=IndentDumper, default_flow_style=False, sort_keys=False)

    print(">>> Done.")

if __name__ == "__main__":
    main()