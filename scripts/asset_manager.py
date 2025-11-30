# [Why] 複雑なアセット配置とコード修正(Patching)を自動化・再現可能にするため
# [What] レシピJSONを読み込み、HFダウンロード・シンボリックリンク作成・文字列置換を行う
# [Input] 環境変数 HF_TOKEN (必須), レシピJSON (ファイル)

import os
import json
import shutil
import sys
from pathlib import Path
from huggingface_hub import hf_hub_download, login

# [Why] 定義ファイル(JSON)をプログラムで扱える形式に変換するため
# [What] 指定されたパスのJSONファイルを読み込み、辞書オブジェクトとして返す
# [Input] path: JSONファイルの絶対パス
def load_recipe(path):
    with open(path, 'r') as f:
        return json.load(f)

# [Why] Gated ModelやLFSファイルのダウンロードに必要な認証を通すため
# [What] 環境変数からトークンを取得し、HuggingFace CLIにログインする
# [Input] os.environ["HF_TOKEN"]
def ensure_token():
    token = os.environ.get("HF_TOKEN")
    if not token:
        print("❌ Error: HF_TOKEN environment variable is not set.")
        sys.exit(1)
    print("🔑 Authenticating with Hugging Face...")
    login(token=token)

# [Why] 必要なモデルファイルをインターネットから取得し、所定の位置に配置するため
# [What] huggingface_hubを使用してダウンロードし、必要に応じてリネーム・移動を行う
# [Input] items: ダウンロード定義のリスト [{"repo_id", "filename", ...}]
def process_downloads(items):
    print("⬇️ Processing downloads...")
    for item in items:
        if item["type"] == "huggingface":
            try:
                print(f"  - Downloading {item['filename']} from {item['repo_id']}...")
                
                # ダウンロード実行 (キャッシュ機構を利用)
                file_path = hf_hub_download(
                    repo_id=item["repo_id"],
                    filename=item["filename"],
                    local_dir=item["target_dir"],
                    local_dir_use_symlinks=False
                )
                
                # リネーム処理 (ComfyUIが期待するファイル名に合わせる場合)
                if "rename_to" in item:
                    target_path = Path(item["target_dir"]) / item["rename_to"]
                    downloaded_path = Path(file_path)
                    
                    shutil.move(downloaded_path, target_path)
                    print(f"    ✅ Renamed to {item['rename_to']}")
                else:
                    print(f"    ✅ Saved to {item['target_dir']}")
                    
            except Exception as e:
                print(f"    ❌ Failed: {e}")

# [Why] 開発者ごとに異なるフォルダ構成の解釈違い(Path inconsistencies)を吸収するため
# [What] 実体ファイルへのシンボリックリンクを、ノードが探索する場所に作成する(絨毯爆撃)
# [Input] items: リンク定義のリスト [{"src", "dest"}]
def process_symlinks(items):
    print("🔗 Processing symlinks...")
    for item in items:
        src = Path(item["src"])
        dest = Path(item["dest"])
        
        # リンク元が存在しなければスキップ
        if not src.exists():
            print(f"    ⚠️ Source not found: {src}")
            continue
            
        # 親ディレクトリがなければ作成
        dest.parent.mkdir(parents=True, exist_ok=True)
        
        # 既存のリンクやファイルがあれば削除して作り直す(冪等性の担保)
        if dest.exists() or dest.is_symlink():
            dest.unlink()
            
        dest.symlink_to(src)
        print(f"    ✅ Linked {dest.name} -> {src.name}")

# [Why] 既存コードのバグや、バージョン不整合によるエラーを修正するため
# [What] 指定されたファイル内の特定文字列を検索し、置換文字列に書き換える(Hot Patching)
# [Input] items: パッチ定義のリスト [{"file", "find", "replace"}]
def process_patches(items):
    print("🩹 Processing patches...")
    for item in items:
        file_path = Path(item["file"])
        if not file_path.exists():
            print(f"    ⚠️ File not found: {file_path}")
            continue
            
        try:
            content = file_path.read_text(encoding="utf-8")
            
            # まだパッチが当たっていない場合のみ適用
            if item["find"] in content:
                new_content = content.replace(item["find"], item["replace"])
                file_path.write_text(new_content, encoding="utf-8")
                print(f"    ✅ Patched {file_path.name}")
            
            # 既にパッチ適用済みの場合
            elif item["replace"] in content:
                print(f"    ℹ️ Already patched: {file_path.name}")
            
            # 検索文字列が見つからない場合(バージョン違いなど)
            else:
                print(f"    ⚠️ Target string not found in {file_path.name}")
                
        except Exception as e:
            print(f"    ❌ Patch failed: {e}")

# [Why] スクリプトのエントリーポイント
# [What] レシピファイルの存在確認、トークン確認、各プロセスの順次実行を行う
def main():
    # レシピファイルのパス (固定)
    recipe_path = "/app/config/takumi_meta/recipes/assets/magic_clothing.json"
    
    if not os.path.exists(recipe_path):
        print(f"❌ Recipe not found: {recipe_path}")
        sys.exit(1)

    recipe = load_recipe(recipe_path)
    print(f"🚀 Starting Asset Manager: {recipe['id']}")
    
    ensure_token()
    
    if "downloads" in recipe:
        process_downloads(recipe["downloads"])
        
    if "symlinks" in recipe:
        process_symlinks(recipe["symlinks"])
        
    if "patches" in recipe:
        process_patches(recipe["patches"])

    print("✨ All assets processed successfully.")

if __name__ == "__main__":
    main()