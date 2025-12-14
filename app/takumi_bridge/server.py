"""
Takumi Bridge Server API

[Why] To provide a backend interface between the ComfyUI frontend and the local AI.
[What] Handles chat requests, manages prompt context, executes inference, and orchestrates workflow loading.
"""

import server
import aiohttp
from aiohttp import web
import json
import os
import subprocess
import sys
from typing import Dict, Any, Optional

# ==============================================================================
# [1] Configuration (Encapsulation)
# ==============================================================================
class TakumiConfig:
    """Central configuration for the bridge module."""
    # AI Settings
    OLLAMA_API_URL = "http://localhost:11434/api/generate"
    # gemma2:2b provides the best balance of speed and instruction following
    MODEL_NAME = "gemma2:2b"
    
    # File Paths
    BASE_CONFIG_DIR = "/app/config/takumi_meta"

    BASE_PROMPT_DIR = f"{BASE_CONFIG_DIR}/prompts"
    PERSONA_PATH = f"{BASE_PROMPT_DIR}/persona.txt"
    CAPABILITIES_PATH = f"{BASE_PROMPT_DIR}/capabilities.txt"

    WORKFLOW_META_PATH = f"{BASE_CONFIG_DIR}/entities/workflows_meta.json"

# ==============================================================================
# [2] Resource Managers (Abstraction)
# ==============================================================================
class ResourceManager:
    """Handles loading of static resources like prompts and metadata."""

    @staticmethod
    def load_workflow_catalog() -> Dict[str, Any]:
        """[What] Loads the workflow definitions from JSON file."""
        if os.path.exists(TakumiConfig.WORKFLOW_META_PATH):
            try:
                with open(TakumiConfig.WORKFLOW_META_PATH, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"[TakumiBridge] Error loading catalog: {e}", file=sys.stderr)
        return {}

    @staticmethod
    def _read_text_file(path: str) -> str:
        """[What] Helper to safely read a text file."""
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return f.read()
            except Exception:
                pass
        return ""

    @classmethod
    def build_full_system_prompt(cls) -> str:
        """
        [Why] To combine Persona (Soul) and Capabilities (Skill) into a single prompt.
        [What] Loads text files, injects catalog data, and merges them.
        """
        
        # 1. Load Components
        persona = cls._read_text_file(TakumiConfig.PERSONA_PATH)
        capabilities = cls._read_text_file(TakumiConfig.CAPABILITIES_PATH)
        
        # Fallback
        if not persona: persona = "You are Takumi."
        if not capabilities: capabilities = "Respond in JSON."

        # 2. Inject Catalog into Capabilities
        catalog = cls.load_workflow_catalog()
        catalog_str = json.dumps(catalog, indent=2)
        
        if "{{WORKFLOW_CATALOG}}" in capabilities:
            capabilities = capabilities.replace("{{WORKFLOW_CATALOG}}", catalog_str)
        else:
            capabilities += f"\n\nWorkflows:\n{catalog_str}"

        # 3. Merge (Soul + Skill)
        return f"{persona}\n\n{capabilities}"

# ==============================================================================
# [3] Workflow Engine (The Worker)
# ==============================================================================
class WorkflowEngine:
    """Handles the logic of finding, loading, and modifying workflow files."""
    
    @staticmethod
    def process_action(ai_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        [Why] To translate AI's abstract intent into concrete ComfyUI graph data.
        [Input] ai_data: Dict containing 'target_id' and 'params'.
        [Output] Dict ready for frontend response (type: action).
        """
        catalog = ResourceManager.load_workflow_catalog()
        target_id_query = ai_data.get("target_id", "").strip().lower()
        
        # 1. Fuzzy Search for Workflow ID
        matched_id = None
        for key in catalog.keys():
            if target_id_query in key.lower():
                matched_id = key
                break
        
        if not matched_id:
            return {"type": "text", "response": f"Sorry, I couldn't find a workflow matching '{target_id_query}'."}

        # 2. Load File
        meta = catalog[matched_id]
        file_path = meta.get("path", "")
        
        if not os.path.exists(file_path):
            return {"type": "text", "response": f"System Error: Workflow file not found at {file_path}"}

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                workflow_json = json.load(f)
        except Exception as e:
            return {"type": "text", "response": f"System Error: Failed to load JSON. {e}"}

        # 3. Dynamic Injection (Modify Prompts)
        params = ai_data.get("params", {})
        mapping = meta.get("mapping", {})
        injected_log = []

        if "prompt" in params and "prompt" in mapping:
            target_node_id = mapping["prompt"]["node_id"]
            widget_index = mapping["prompt"]["widget_index"]
            new_prompt = params["prompt"]
            
            # Search for the node and update it
            for node in workflow_json.get("nodes", []):
                if node["id"] == target_node_id:
                    if "widgets_values" in node and len(node["widgets_values"]) > widget_index:
                        node["widgets_values"][widget_index] = new_prompt
                        injected_log.append(f"Prompt updated to: '{new_prompt}'")
                    break

        # 4. Construct Success Response
        message = f"Loaded workflow: **{meta.get('name', matched_id)}**"
        if injected_log:
            message += f"\n(Auto-configured: {', '.join(injected_log)})"

        return {
            "type": "action",
            "message": message,
            "workflow": workflow_json
        }

# ==============================================================================
# [4] AI Client (Networking)
# ==============================================================================
class OllamaClient:
    """Handles HTTP communication with the local Ollama instance."""

    @staticmethod
    async def query(user_input: str, system_prompt: str) -> Dict[str, Any]:
        """
        [Why] To execute inference and handle potential JSON parsing issues.
        [What] Sends POST request, cleans Markdown from response, and parses JSON.
        """
        payload = {
            "model": TakumiConfig.MODEL_NAME,
            "prompt": user_input,
            "system": system_prompt,
            "stream": False,
            "format": "json"
        }
        
        print(f">>> [Takumi] User: {user_input}", file=sys.stderr)

        async with aiohttp.ClientSession() as session:
            try:
                async with session.post(TakumiConfig.OLLAMA_API_URL, json=payload) as resp:
                    if resp.status == 404:
                        await OllamaClient._pull_model()
                        return await OllamaClient.query(user_input, system_prompt) # Retry
                    
                    if resp.status != 200:
                        return {"error": f"Ollama Error: {resp.status}"}
                    
                    ollama_res = await resp.json()
                    ai_text = ollama_res.get("response", "")
                    print(f">>> [Takumi] AI Raw: {ai_text}", file=sys.stderr)

                    # [Sanitization] Remove Markdown code blocks if present
                    clean_text = ai_text.strip()
                    if clean_text.startswith("```json"): clean_text = clean_text[7:]
                    if clean_text.endswith("```"): clean_text = clean_text[:-3]
                    
                    try:
                        return json.loads(clean_text.strip())
                    except json.JSONDecodeError:
                        # Fallback: Treat as normal text response
                        return {"response": ai_text}

            except Exception as e:
                return {"error": f"Connection Error: {e}"}

    @staticmethod
    async def _pull_model():
        """[Why] Self-healing mechanism for missing models."""
        print(f">>> [Takumi] Pulling model {TakumiConfig.MODEL_NAME}...", file=sys.stderr)
        subprocess.run(["ollama", "pull", TakumiConfig.MODEL_NAME], check=True)

# ==============================================================================
# [5] Route Handler (Controller)
# ==============================================================================
@server.PromptServer.instance.routes.post("/takumi/chat")
async def chat_handler(request):
    """
    [Input] Request JSON: { "prompt": "user message" }
    [Output] Response JSON: { "type": "text"|"action", ... }
    """
    try:
        req_data = await request.json()
        user_prompt = req_data.get("prompt", "")

        # 1. AI Inference
        system_prompt = ResourceManager.build_full_system_prompt()
        ai_data = await OllamaClient.query(user_prompt, system_prompt)

        # 2. Error Check
        if "error" in ai_data:
            return web.json_response({"type": "text", "response": ai_data["error"]})

        # 3. Action Dispatch
        if "action" in ai_data and ai_data["action"] == "load_workflow":
            response_data = WorkflowEngine.process_action(ai_data)
            return web.json_response(response_data)
        
        # 4. Normal Conversation
        if "response" in ai_data:
            return web.json_response({"type": "text", "response": ai_data["response"]})

        # 5. Fallback
        return web.json_response({"type": "text", "response": str(ai_data)})

    except Exception as e:
        print(f"[TakumiBridge] Critical Error: {e}", file=sys.stderr)
        return web.json_response({"type": "text", "response": "Internal Server Error."})