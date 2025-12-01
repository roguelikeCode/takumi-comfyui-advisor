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
        
        catalog = load_workflow_catalog()
        catalog_str = json.dumps(catalog, indent=2)

        # [Update] System Prompt: パラメータ抽出を指示
        system_prompt = (
            f"You are Takumi, an AI assistant for ComfyUI. "
            f"Available workflows:\n{catalog_str}\n\n"
            "Rules:\n"
            "1. If the user wants to generate an image or use a workflow, return a JSON object with: "
            "{\"action\": \"load_workflow\", \"target_id\": \"<id>\", \"params\": {\"prompt\": \"<english_visual_description>\"}}\n"
            "   - Translate the user's request into a detailed English prompt for Stable Diffusion.\n"
            "2. If it's a normal chat, return: {\"response\": \"<answer_in_japanese>\"}"
        )

        ollama_payload = {
            "model": MODEL_NAME,
            "prompt": user_prompt,
            "system": system_prompt,
            "stream": False,
            "format": "json"
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(OLLAMA_API_URL, json=ollama_payload) as resp:
                if resp.status != 200:
                    return web.Response(text=f"Ollama Error: {resp.status}", status=500)
                
                ollama_res = await resp.json()
                ai_response_str = ollama_res.get("response", "")
                print(f">>> [TakumiBridge] Raw AI Response: {ai_response_str}")

                try:
                    ai_data = json.loads(ai_response_str)
                    
                    # Case 1: Action (Workflow Load)
                    if "action" in ai_data and ai_data["action"] == "load_workflow":
                        target_id = None
                        raw_id = ai_data.get("target_id", "").strip()
                        
                        # Fuzzy Search
                        for key in catalog.keys():
                            if raw_id.lower() in key.lower():
                                target_id = key
                                break
                        
                        if target_id:
                            meta = catalog[target_id]
                            file_path = meta["path"]
                            
                            if os.path.exists(file_path):
                                with open(file_path, 'r') as wf:
                                    workflow_json = json.load(wf)
                                
                                # [New] Dynamic Injection (動的注入)
                                params = ai_data.get("params", {})
                                mapping = meta.get("mapping", {})
                                injected_log = []

                                if "prompt" in params and "prompt" in mapping:
                                    # 地図(mapping)に従って書き換える
                                    target_node_id = mapping["prompt"]["node_id"]
                                    widget_index = mapping["prompt"]["widget_index"]
                                    new_prompt_text = params["prompt"]
                                    
                                    # ノードを探して書き換え
                                    for node in workflow_json.get("nodes", []):
                                        if node["id"] == target_node_id:
                                            # ウィジェット配列の値を更新
                                            if len(node["widgets_values"]) > widget_index:
                                                node["widgets_values"][widget_index] = new_prompt_text
                                                injected_log.append(f"Prompt -> '{new_prompt_text}'")
                                            break

                                message = f"ワークフロー '{meta['name']}' をロードします。"
                                if injected_log:
                                    message += f"\n(設定変更: {', '.join(injected_log)})"

                                return web.json_response({
                                    "type": "action",
                                    "message": message,
                                    "workflow": workflow_json
                                })
                            else:
                                return web.json_response({"type": "text", "response": f"Error: File not found ({file_path})"})
                        else:
                            return web.json_response({"type": "text", "response": f"Workflow '{raw_id}' not found."})

                    # Case 2: Normal Talk
                    elif "response" in ai_data:
                        return web.json_response({"type": "text", "response": ai_data["response"]})
                    
                    else:
                        return web.json_response({"type": "text", "response": ai_response_str})

                except json.JSONDecodeError:
                    return web.json_response({"type": "text", "response": ai_response_str})

    except Exception as e:
        print(f"[TakumiBridge] Error: {e}")
        return web.json_response({"type": "text", "response": f"System Error: {str(e)}"})