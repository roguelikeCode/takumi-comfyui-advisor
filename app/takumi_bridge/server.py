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
MODEL_NAME = "gemma3" # 7B Model
META_PATH = "/app/config/takumi_meta/entities/workflows_meta.json"

@server.PromptServer.instance.routes.post("/takumi/chat")
async def chat_handler(request):
    try:
        data = await request.json()
        user_prompt = data.get("prompt", "")
        
        # [Context Injection]
        # ここで将来的に「現在のワークフロー情報」や「カタログ情報」をプロンプトに注入する
        # 今回はシンプルにパススルーする
        system_prompt = (
            "You are Takumi, an expert AI assistant for ComfyUI. "
            "Answer concisely in Japanese. "
            "If asked about workflows, refer to the 'Magic Clothing' workflow."
        )

        ollama_payload = {
            "model": MODEL_NAME,
            "prompt": user_prompt,
            "system": system_prompt,
            "stream": False # 初回は非ストリーミングで確実に実装
        }

        # Ollamaへのリクエスト (aiohttpを使用)
        async with aiohttp.ClientSession() as session:
            async with session.post(OLLAMA_API_URL, json=ollama_payload) as resp:
                if resp.status != 200:
                    return web.Response(text=f"Ollama Error: {resp.status}", status=500)
                
                ollama_res = await resp.json()
                ai_text = ollama_res.get("response", "")
                
                return web.json_response({"response": ai_text})

    except Exception as e:
        print(f"[TakumiBridge] Error: {e}")
        return web.Response(text=str(e), status=500)

print(">>> [TakumiBridge] Nexus API initialized.")