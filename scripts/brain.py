# [Why] インストーラーやコンシェルジュから、ローカルLLM(Ollama)を同期的に呼び出すため
# [What] 標準ライブラリのみでOllama APIを叩く軽量クライアント
# [Input] コマンドライン引数としてプロンプトを受け取る

import sys
import json
import urllib.request
import urllib.error
import time
import subprocess

# --- Configuration ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"
# [Update] Pilotの意思決定により、最新のGemma 3を採用。
# Ollamaはデフォルトで最適な量子化モデル(4-bit等)をpullします。
MODEL_NAME = "gemma3" 

def ensure_ollama_running():
    """
    [Why] Ollamaサーバーが起動していない場合にバックグラウンドで起動する
    """
    try:
        urllib.request.urlopen(OLLAMA_API_URL.replace("/api/generate", ""), timeout=1)
    except (urllib.error.URLError, ConnectionRefusedError):
        print(">>> [Brain] Starting Ollama server...", file=sys.stderr)
        subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # 起動待機 (最大10秒)
        for _ in range(10):
            try:
                urllib.request.urlopen(OLLAMA_API_URL.replace("/api/generate", ""), timeout=1)
                print(">>> [Brain] Ollama is ready.", file=sys.stderr)
                return
            except:
                time.sleep(1)
        print(">>> [Brain] Error: Failed to start Ollama.", file=sys.stderr)
        sys.exit(1)

def ensure_model_pulled():
    """
    [Why] 指定されたモデルが存在しない場合、pullを実行する
    """
    # 簡易的なチェック: pullは冪等性があるので毎回呼んでも良いが、遅くなるのでリスト確認推奨
    # 今回はシンプルに、generateリクエストを投げて404が返ってきたらpullする戦略をとる
    pass 

def query_ollama(prompt):
    """
    [Why] Ollamaにプロンプトを投げ、レスポンスを取得する
    """
    payload = {
        "model": MODEL_NAME,
        "prompt": prompt,
        "stream": False,
        "system": "あなたは「Takumi」という名の、熟練したシステムエンジニア兼コンシェルジュです。日本語で、簡潔かつ的確に答えてください。"
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(OLLAMA_API_URL, data=data, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result.get("response", "")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # モデルが見つからない場合
            print(f">>> [Brain] Model '{MODEL_NAME}' not found. Pulling now... (This may take a while)", file=sys.stderr)
            subprocess.run(["ollama", "pull", MODEL_NAME], check=True)
            # 再帰呼び出し
            return query_ollama(prompt)
        else:
            raise e

def main():
    if len(sys.argv) < 2:
        print("Usage: python brain.py <prompt>")
        sys.exit(1)

    prompt = sys.argv[1]
    
    ensure_ollama_running()
    
    try:
        response = query_ollama(prompt)
        print(response)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()