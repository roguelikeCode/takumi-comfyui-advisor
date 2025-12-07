# [Why] インストール失敗時の状況を収集するため
# [What] 環境情報、エラーログ、レシピを収集・匿名化し、AWSへ送信する
# [Input] args: log_file_path, recipe_path

import sys
import json
import os
import platform
import urllib.request
import re
from datetime import datetime, timezone

# --- Configuration ---
# 以前の install.sh にあったAPI URLを使用 (本番用に適宜変更してください)
API_URL = "https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"

def sanitize_path(text):
    """
    [Why] ユーザー名などの個人情報を隠蔽するため
    [What] /home/username を /home/<USER> に置換する
    """
    if not text:
        return ""
    # ユーザーのホームディレクトリを取得
    home = os.path.expanduser("~")
    return text.replace(home, "/home/<USER>")

def get_system_info():
    """最小限のシステム情報を取得"""
    return {
        "os": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python_version": sys.version.split()[0]
    }

def read_last_logs(log_path, lines=50):
    """ログファイルの末尾N行を取得"""
    if not os.path.exists(log_path):
        return ["Log file not found."]
    
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            # 簡易的な実装: 全読みして末尾を取得 (巨大ログの場合はseekを使うべきだが今回は簡易版)
            content = f.readlines()
            return [sanitize_path(line.strip()) for line in content[-lines:]]
    except Exception as e:
        return [f"Error reading log: {str(e)}"]

def load_recipe(recipe_path):
    """実行しようとしていたレシピの内容を取得"""
    if recipe_path and os.path.exists(recipe_path):
        try:
            with open(recipe_path, 'r') as f:
                return json.load(f)
        except:
            return {"error": "Failed to load recipe"}
    return None

def send_report(payload):
    """AWS LambdaへJSONをPOST送信"""
    try:
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(API_URL, data=data, headers={
            'Content-Type': 'application/json',
            'User-Agent': 'Takumi-Installer/1.0'
        })
        with urllib.request.urlopen(req) as res:
            print(f">>> [Report] Failure log sent. ID: {res.read().decode('utf-8')}")
    except Exception as e:
        # 送信失敗はユーザー体験を阻害しないよう、静かに警告だけ出す
        print(f">>> [Report] Failed to send log: {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python report_failure.py <log_file> [recipe_file]")
        return

    log_file = sys.argv[1]
    recipe_file = sys.argv[2] if len(sys.argv) > 2 else None

    print("\n>>> [Takumi] ⚠️  Installation failed. Gathering diagnostics...")

    payload = {
        "event_type": "install_failure",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "system_info": get_system_info(),
        "error_log": read_last_logs(log_file),
        "target_recipe": load_recipe(recipe_file)
    }

    # デバッグ用: ローカルに保存
    # with open("last_failure_report.json", "w") as f:
    #    json.dump(payload, f, indent=2)

    print(">>> [Takumi] Sending anonymous crash report to improve future versions...")
    send_report(payload)

if __name__ == "__main__":
    main()