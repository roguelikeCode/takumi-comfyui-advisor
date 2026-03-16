"""
Takumi Bridge Server API (v3.2 Elegant Edition)

[Why] To act as the intelligent interface between the User and ComfyUI.
[What] Handles chat requests, resolves intents via Fast Path or AI, and orchestrates workflow deployments.
"""

import server
import aiohttp
from aiohttp import web
import json
import os
import sys
import subprocess
import asyncio
from typing import Dict, Any, Optional

# ==============================================================================
# [1] Configuration & Constants
# ==============================================================================
class TakumiConfig:
    """
    Central Configuration Registry.
    [Why] To unify path resolution and external service endpoints.
    """

    # --- File System Paths ---
    WORKFLOW_REGISTRY_DIR: str = "/app/external/takumi-registry"
    
    # --- AI Service Settings (Ollama) ---
    # [Logic] Retrieve host from environment, strip '/v1' suffix to ensure raw API access.
    _raw_host: str = os.getenv("OLLAMA_HOST", "http://ollama:11434")
    _sanitized_host: str = _raw_host.replace("/v1", "").rstrip("/")
    
    OLLAMA_API_URL: str = f"{_sanitized_host}/api/generate"
    MODEL_NAME: str = "gemma3:4b"
    
    # --- File System Paths ---
    WORKFLOW_REGISTRY_DIR: str = "/app/external/takumi-registry"
    COMFY_ROOT: str = "/app/external/ComfyUI"
    CUSTOM_NODES_DIR: str = os.path.join(COMFY_ROOT, "custom_nodes")

    @classmethod
    def get_asset_path(cls, rel_path: str) -> str:
        """
        [Why] To resolve file paths directly from the flat Event Store.
        """
        return os.path.join(cls.WORKFLOW_REGISTRY_DIR, rel_path)

# ==============================================================================
# [2] Catalog Manager (The Librarian)
# ==============================================================================
class CatalogManager:
    """Handles loading, validating, and formatting workflow metadata."""

    @staticmethod
    def load_validated_catalog() -> Dict[str, Any]:
        """
        [Why] To load metadata and filter out unavailable workflows.
        """
        raw_catalog: Dict[str, Any] = {}
        
        # 1. [Zero-State] Flat structure lookup
        path = os.path.join(TakumiConfig.WORKFLOW_REGISTRY_DIR, "entities", "workflows_meta.json")
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    raw_catalog.update(json.load(f))
            except Exception as e:
                print(f">>> [Takumi] Error loading catalog: {e}", file=sys.stderr)

        # 2. Validate Availability (Receipt Check)
        valid_catalog: Dict[str, Any] = {}
        receipts_dir = "/app/storage/receipts"

        for key, val in raw_catalog.items():
            required_asset_id = val.get("requires_asset")
            
            if required_asset_id:
                receipt_path = os.path.join(receipts_dir, required_asset_id)
                # Skip if the required receipt (proof of installation) is missing
                if not os.path.exists(receipt_path):
                    continue
            
            valid_catalog[key] = val
            
        return valid_catalog

    @staticmethod
    def build_system_prompt() -> str:
        """
        [Why] To construct the AI context using the current catalog state.
        [What] Injects both logic definitions (for AI) and menu formatting (for UI).
        """
        prompt_path = TakumiConfig.get_asset_path("prompts/capabilities.txt")
        if not os.path.exists(prompt_path):
            return "You are a smart router. Output valid JSON only."
        
        with open(prompt_path, 'r', encoding='utf-8') as f:
            base_prompt = f.read()

        persona_path = TakumiConfig.get_asset_path("prompts/persona.txt")
        persona = ""
        if os.path.exists(persona_path):
             with open(persona_path, 'r', encoding='utf-8') as f:
                persona = f.read()

        catalog = CatalogManager.load_validated_catalog()
        logic_lines = []
        menu_lines =[]

        for key, val in catalog.items():
            name = val.get("name", "Unknown")
            tags = ", ".join(val.get("tags", []))
            logic_lines.append(f"[{key}] {name} | Tags: {tags}")
            menu_lines.append(f"🔹 {name}")

        full_prompt = base_prompt.replace("{{WORKFLOW_CATALOG}}", "\n".join(logic_lines))
        full_prompt = full_prompt.replace("{{WORKFLOW_MENU}}", "\n".join(menu_lines))

        return f"{persona}\n\n{full_prompt}" if persona else full_prompt

# ==============================================================================
# [3] Intent Resolver (The Brain)
# ==============================================================================
class IntentResolver:
    """Decides whether to route the request via Fast Path (Regex/Match) or AI Inference."""

    @staticmethod
    async def resolve(user_input: str) -> Dict[str, Any]:
        """
        [Why] To determine the fastest and most accurate response mechanism.
        """
        # Strategy A: Fast Path (Deterministic Match)
        catalog = CatalogManager.load_validated_catalog()
        clean_input = user_input.replace("🔹", "").replace("▶", "").strip().lower()

        for wf_id, meta in catalog.items():
            if clean_input == meta.get("name", "").strip().lower():
                print(f">>> [Takumi] Fast Path Triggered: {wf_id}", file=sys.stderr)
                return {
                    "action": "load_workflow",
                    "target_id": wf_id,
                    "params": {}
                }

        # Strategy B: AI Inference (Ollama)
        result = await IntentResolver._query_ollama(user_input)
        
        # Guard against NoneType parsing failures
        if result is None:
            return {"type": "text", "response": "🧠 Inference interrupted. Please try again."}
        return result

    @staticmethod
    async def _query_ollama(user_input: str) -> Optional[Dict[str, Any]]:
        """
        [Why] To execute semantic routing and handle AI lifecycle states.
        """
        system_prompt = CatalogManager.build_system_prompt()
        payload = {
            "model": TakumiConfig.MODEL_NAME,
            "prompt": user_input,
            "system": system_prompt,
            "stream": False,
            "format": "json",
            # [Optimization] Unload from VRAM aggressively after 20 seconds
            "keep_alive": "20s" 
        }

        print(f">>>[Takumi] AI Query Initiated: {user_input}", file=sys.stderr)
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(TakumiConfig.OLLAMA_API_URL, json=payload) as resp:
                    # Handle uninitialized model state
                    if resp.status == 404:
                        model_name = TakumiConfig.MODEL_NAME
                        asyncio.create_task(IntentResolver._simple_pull_bg(model_name))
                        return {
                            "type": "downloading",
                            "response": f"🧠 Initializing AI Model ({model_name}).\n\nDue to the large data size, this process will take a few minutes.\n\nThe interface may temporarily appear unresponsive, but processing continues in the background. Please wait a moment before trying again.",
                        }
                    
                    if resp.status != 200:
                        return {"type": "text", "response": f"AI Error: HTTP {resp.status}"}
                    
                    data = await resp.json()
                    return IntentResolver._parse_ai_response(data.get("response", ""))
        except Exception as e:
            return {"type": "text", "response": f"Connection Error: {str(e)}"}
        
    @staticmethod
    async def _simple_pull_bg(model_name: str) -> None:
        """[Why] To reliably and silently download the model using the CLI in the background.
        """
        print(f"\n>>> [Takumi] 📥 Downloading model '{model_name}' in background...", file=sys.stderr)
        try:
            proc = await asyncio.create_subprocess_exec(
                "ollama", "pull", model_name,
                env=os.environ.copy()  # [Zero-State] Ensure that parental environment variables are inherited.
            )
            await proc.wait()
            if proc.returncode == 0:
                print(f">>> [Takumi] ✅ Model '{model_name}' downloaded successfully.", file=sys.stderr)
            else:
                print(f">>> [Takumi] ❌ Failed to download model (exit code: {proc.returncode}).", file=sys.stderr)
        except Exception as e:
            print(f">>>[Takumi] ❌ Error pulling model: {str(e)}", file=sys.stderr)

    @staticmethod
    def _parse_ai_response(raw_text: str) -> Dict[str, Any]:
        """[What] Cleans markdown wrappers and parses the JSON response."""
        if not raw_text: 
            return {"type": "text", "response": "..."}
            
        try:
            clean_text = raw_text.strip()
            if clean_text.startswith("```json"): 
                clean_text = clean_text[7:]
            if clean_text.endswith("```"): 
                clean_text = clean_text[:-3]
            return json.loads(clean_text)
        except json.JSONDecodeError:
            return {"type": "text", "response": raw_text}

# ==============================================================================
# [4] Workflow Executor (The Worker)
# ==============================================================================
class WorkflowExecutor:
    """Translates an Action ID into actual ComfyUI graph data."""

    @staticmethod
    def execute(action_data: Dict[str, Any]) -> Dict[str, Any]:
        target_id = action_data.get("target_id")
        catalog = CatalogManager.load_validated_catalog()
        
        if target_id not in catalog:
            return {"type": "text", "response": f"Workflow ID '{target_id}' not found."}

        meta = catalog[target_id]
        path = meta.get("path")
        
        if not os.path.exists(path):
            return {"type": "text", "response": f"File not found: {path}"}
            
        try:
            with open(path, 'r', encoding='utf-8') as f:
                workflow = json.load(f)
        except Exception as e:
            return {"type": "text", "response": f"Invalid JSON format: {str(e)}"}

        # Inject dynamic parameters (e.g., prompt replacements)
        params = action_data.get("params", {})
        mapping = meta.get("mapping", {})
        injected =[]

        if "prompt" in params and "prompt" in mapping:
            node_id = mapping["prompt"]["node_id"]
            idx = mapping["prompt"]["widget_index"]
            new_val = params["prompt"]
            
            for node in workflow.get("nodes", []):
                if node["id"] == node_id:
                    if len(node["widgets_values"]) > idx:
                        node["widgets_values"][idx] = new_val
                        injected.append("Prompt updated")
                        break

        # Construct final response
        msg = f"Loaded: {meta.get('name')}"
        if injected: 
            msg += f"\n({', '.join(injected)})"

        return {
            "type": "action",
            "message": msg,
            "workflow": workflow
        }

# ==============================================================================
# [5] Route Handler (The Controller)
# ==============================================================================
@server.PromptServer.instance.routes.get("/takumi/catalog")
async def get_catalog(request) -> web.Response:
    """
    [Why] API endpoint for the frontend to render the Zero-Compute Menu.
    """
    catalog = CatalogManager.load_validated_catalog()
    return web.json_response(catalog)

@server.PromptServer.instance.routes.post("/takumi/chat")
async def chat_handler(request) -> web.Response:
    """
    [Why] Primary entry point for user interactions from the Takumi UI.
    """
    try:
        req_data = await request.json()
        user_prompt = req_data.get("prompt", "").strip()
        
        if not user_prompt:
            return web.json_response({"type": "text", "response": "..."})

        # 1. Resolve Intent
        ai_result = await IntentResolver.resolve(user_prompt)

        # 2. Execute Action
        if ai_result.get("action") == "load_workflow":
            response_payload = WorkflowExecutor.execute(ai_result)
            return web.json_response(response_payload)

        # 3. Return Text Response
        return web.json_response(ai_result)
        
    except Exception as e:
        print(f">>> [Takumi] Critical Error: {str(e)}", file=sys.stderr)
        return web.json_response({"type": "text", "response": f"Internal Server Error: {str(e)}"})