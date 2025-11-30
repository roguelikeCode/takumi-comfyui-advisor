# [Why] 複雑なアセット配置とコード修正(Patching)を自動化するため
# [What] レシピJSONを読み込み、HFダウンロード・シンボリックリンク作成・文字列置換を行う
# [Input] 環境変数 HF_TOKEN (必須)

import os
import json
import shutil
import sys
from pathlib import Path
from huggingface_hub import hf_hub_download, login

def load_recipe(path):
    with open(path, 'r') as f:
        return json.load(f)

def ensure_token():
    token = os.environ.get("HF_TOKEN")
    if not token:
        print("❌ Error: HF_TOKEN environment variable is not set.")
        sys.exit(1)
    print("🔑 Authenticating with Hugging Face...")
    login(token=token)

def process_downloads(items):
    print("⬇️ Processing downloads...")
    for item in items:
        if item["type"] == "huggingface":
            try:
                print(f"  - Downloading {item['filename']} from {item['repo_id']}...")
                
                # ダウンロード (Cacheを活用)
                file_path = hf_hub_download(
                    repo_id=item["repo_id"],
                    filename=item["filename"],
                    local_dir=item["target_dir"],
                    local_dir_use_symlinks=False
                )
                
                # リネームが必要な場合
                if "rename_to" in item:
                    target_path = Path(item["target_dir"]) / item["rename_to"]
                    # hf_hub_download は指定した filename で保存するので、それをリネーム
                    # (注意: filenameにスラッシュが含まれる場合のケアが必要だが、今回は簡易実装)
                    downloaded_path = Path(file_path) # hf_hub_downloadが返す絶対パス
                    
                    # 移動 (上書き)
                    shutil.move(downloaded_path, target_path)
                    print(f"    ✅ Renamed to {item['rename_to']}")
                else:
                    print(f"    ✅ Saved to {item['target_dir']}")
                    
            except Exception as e:
                print(f"    ❌ Failed: {e}")

def process_symlinks(items):
    print("🔗 Processing symlinks...")
    for item in items:
        src = Path(item["src"])
        dest = Path(item["dest"])
        
        if not src.exists():
            print(f"    ⚠️ Source not found: {src}")
            continue
            
        dest.parent.mkdir(parents=True, exist_ok=True)
        
        if dest.exists() or dest.is_symlink():
            dest.unlink() # 既存のものを削除
            
        dest.symlink_to(src)
        print(f"    ✅ Linked {dest.name} -> {src.name}")

def process_patches(items):
    print("🩹 Processing patches...")
    for item in items:
        file_path = Path(item["file"])
        if not file_path.exists():
            print(f"    ⚠️ File not found: {file_path}")
            continue
            
        try:
            content = file_path.read_text(encoding="utf-8")
            if item["find"] in content:
                new_content = content.replace(item["find"], item["replace"])
                file_path.write_text(new_content, encoding="utf-8")
                print(f"    ✅ Patched {file_path.name}")
            elif item["replace"] in content:
                print(f"    ℹ️ Already patched: {file_path.name}")
            else:
                print(f"    ⚠️ Target string not found in {file_path.name}")
        except Exception as e:
            print(f"    ❌ Patch failed: {e}")

def main():
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