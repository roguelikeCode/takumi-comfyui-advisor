# [Why] ブラウザ(UI)と脳(Ollama/Gemma)をつなぐAPIエンドポイントを提供するため
# [What] ComfyUIのサーバー機能にフックし、/takumi/chat へのリクエストをOllamaに転送する
# [Input] Request (JSON with prompt)
# [Output] Streaming Response (from Ollama)

import server
import aiohttp
from aiohttp import web
import json
import os

# --- Configuration ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "gemma3"
META_PATH = "/app/config/takumi_meta/entities/workflows_meta.json"

def load_workflow_catalog():
    """ワークフローのメタデータをロードする"""
    if os.path.exists(META_PATH):
        with open(META_PATH, 'r') as f:
            return json.load(f)
    return {}

@server.PromptServer.instance.routes.post("/takumi/chat")
async def chat_handler(request):
    try:
        data = await request.json()
        user_prompt = data.get("prompt", "")
        
        # 1. カタログの準備
        catalog = load_workflow_catalog()
        catalog_str = json.dumps(catalog, indent=2)

        # 2. System Prompt (Intent Detection)
        # AIに「通常会話」か「ワークフロー実行」かを判断させる
        system_prompt = (
            f"You are Takumi, an AI assistant for ComfyUI. "
            f"Here is the list of available workflows:\n{catalog_str}\n\n"
            "Rules:\n"
            "1. If the user asks to load or use a workflow, return ONLY a JSON object with this format: "
            "{\"action\": \"load_workflow\", \"target_id\": \"<workflow_id_from_catalog>\"}\n"
            "2. If the user asks a normal question, answer normally in Japanese text."
        )

        ollama_payload = {
            "model": MODEL_NAME,
            "prompt": user_prompt,
            "system": system_prompt,
            "stream": False,
            "format": "json" # Gemma 3にJSONモードを強制（精度向上）
        }

        # 3. Ollamaへ問い合わせ
        async with aiohttp.ClientSession() as session:
            async with session.post(OLLAMA_API_URL, json=ollama_payload) as resp:
                if resp.status != 200:
                    return web.Response(text=f"Ollama Error: {resp.status}", status=500)
                
                ollama_res = await resp.json()
                ai_response_str = ollama_res.get("response", "")
                
                # 4. レスポンスの解析 (Action or Talk)
                try:
                    # AIがJSONを返してきた場合 (Action)
                    ai_data = json.loads(ai_response_str)
                    
                    if "action" in ai_data and ai_data["action"] == "load_workflow":
                        target_id = ai_data["target_id"]
                        
                        # 実際のワークフローファイル(.json)をロードする
                        if target_id in catalog:
                            file_path = catalog[target_id]["path"]
                            if os.path.exists(file_path):
                                with open(file_path, 'r') as wf:
                                    workflow_json = json.load(wf)
                                    
                                return web.json_response({
                                    "type": "action",
                                    "message": f"ワークフロー '{target_id}' をロードします。",
                                    "workflow": workflow_json
                                })
                            else:
                                return web.json_response({"type": "text", "response": f"エラー: ファイルが見つかりません ({file_path})"})
                        else:
                            return web.json_response({"type": "text", "response": "指定されたワークフローIDが見つかりません。"})
                    
                    # AIが普通のJSON会話を返してきた場合 (Talk)
                    response_text = ai_data.get("response", str(ai_data))
                    return web.json_response({"type": "text", "response": response_text})

                except json.JSONDecodeError:
                    # JSONパース失敗時はそのままテキストとして返す (Backup)
                    return web.json_response({"type": "text", "response": ai_response_str})

    except Exception as e:
        print(f"[TakumiBridge] Error: {e}")
        return web.Response(text=str(e), status=500)