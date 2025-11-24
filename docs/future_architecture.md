# 将来のアーキテクチャ構想 (ユーザー投稿の取り込み)

## 1. 目的
ユーザーから送信された `pyproject.toml` (または poetry.lock) を解析し、
自動的にマスターデータ (`external/pyproject.toml`) の `[tool.takumi]` セクションにマージしたい。

## 構想しているフロー
1. ユーザー: ローカルで環境構築完了 -> `poetry export` または `toml` 送信。
2. サーバー:
    - 受け取ったTOMLと、既存のマスターデータを比較。
    - 新しい依存関係があれば、マスターデータの `dependencies` に追記。
    - 新しいカスタムノードがあれば、`custom_nodes_meta.json` に追記。
3. マージ:
    - コンフリクト解消ロジックが必要（同じライブラリのバージョン違いなど）。

## TODO
- `install.sh` の安定稼働後、Pythonスクリプト (`scripts/ingest_user_data.py`) を作成する。


## 2. 参考コード (プロトタイプ)

以前作成した `manifest_builder.py` のプロトタイプコード。
将来、自動化ツールを作成する際のベースとして使用する。

\`\`\`python
import tomllib
import json
import os

# ... (ここに manifest_builder.py の全コードを貼り付ける) ...
\`\`\`

import sys
import json
import os

# Python 3.11以上なら標準ライブラリ、それ未満なら `pip install tomli` が必要
try:
    import tomllib
except ImportError:
    import tomli as tomllib

# --- 設定 ---
INPUT_FILE = "external/pyproject.toml"
OUTPUT_FILE = "app/config/recipes/use_cases/create_and_dress_up_original_fashion.json"

def load_toml(path):
    if not os.path.exists(path):
        print(f"Error: Input file not found at {path}")
        sys.exit(1)
    with open(path, "rb") as f:
        return tomllib.load(f)

def build_components_list(toml_data):
    """
    TOMLのデータから、GraphAIスタイルのcomponentsリスト（Pip + Custom Nodes）を生成する
    """
    components = []

    # 1. Custom Nodes の抽出
    # [tool.takumi.custom_nodes] セクション
    takumi_tools = toml_data.get("tool", {}).get("takumi", {})
    custom_nodes = takumi_tools.get("custom_nodes", {})

    for node_id, version in custom_nodes.items():
        components.append({
            "type": "custom-node",
            "source": node_id,
            "version": version
        })

    # 2. Pip Packages の抽出
    # [tool.poetry.dependencies] セクション
    poetry_deps = toml_data.get("tool", {}).get("poetry", {}).get("dependencies", {})

    for pkg_name, version_spec in poetry_deps.items():
        if pkg_name == "python":
            continue # python自体のバージョンはconda環境定義で扱うため除外
        
        # Note: Poetryのバージョン指定(^1.0など)をPip形式(>=1.0)に変換するロジックが
        # 厳密には必要だが、ここではTOMLに "==1.0" のように書かれていると仮定してそのまま渡す。
        components.append({
            "type": "pip",
            "source": pkg_name,
            "version": str(version_spec)
        })

    return components

def main():
    print(f">>> Reading master data from {INPUT_FILE}...")
    data = load_toml(INPUT_FILE)
    
    takumi_data = data.get("tool", {}).get("takumi", {})
    
    # JSON構造の組み立て
    manifest = {
        # --- Metadata ---
        "asset_id": takumi_data.get("metadata", {}).get("asset_id", "unknown-id"),
        "asset_version": takumi_data.get("metadata", {}).get("asset_version", "0.0.0"),
        "display_name": takumi_data.get("metadata", {}).get("display_name", "No Name"),
        "description": takumi_data.get("metadata", {}).get("description", ""),
        
        # --- Contribution ---
        # TOMLの構造をそのままマッピング
        "contribution": takumi_data.get("contribution", {}).get("groups", []),

        # --- Environment ---
        "environment": takumi_data.get("environment", {}),
        
        # --- Components (Merged) ---
        "components": build_components_list(data)
    }

    # JSON出力
    print(f">>> Generating manifest to {OUTPUT_FILE}...")
    
    # ディレクトリがなければ作成
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        # ensure_ascii=False で日本語などが文字化けしないようにする
        # indent=2 で人間にも読みやすい形式にする
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n') # 末尾に改行を追加

    print(">>> Done. Manifest build complete.")

if __name__ == "__main__":
    main()