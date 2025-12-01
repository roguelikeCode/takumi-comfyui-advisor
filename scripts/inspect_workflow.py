# [Why] ワークフロー内のノードIDとクラス名を特定し、メタデータ作成を支援するため
# [What] 指定されたワークフローJSONを読み込み、ノード一覧を見やすく表示する
import json
import sys

def main():
    # 対象ファイル
    file_path = "app/assets/workflows/magic_clothing_v1.json"
    
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            
        print(f"🔍 Analyzing: {file_path}")
        print("-" * 60)
        print(f"{'ID':<5} | {'Class Type':<30} | {'Title / Widgets'}")
        print("-" * 60)

        nodes = data.get("nodes", [])
        for node in nodes:
            node_id = node.get("id")
            class_type = node.get("type")
            title = node.get("title", class_type)
            
            # ウィジェット（設定値）の中身をチラ見せ
            widgets = node.get("widgets_values", [])
            widgets_str = str(widgets)[:50] + "..." if len(str(widgets)) > 50 else str(widgets)
            
            print(f"{node_id:<5} | {class_type:<30} | {title}")
            print(f"      > Widgets: {widgets_str}")
            print("-" * 60)

    except FileNotFoundError:
        print("❌ File not found. Make sure you ran the download step.")

if __name__ == "__main__":
    main()