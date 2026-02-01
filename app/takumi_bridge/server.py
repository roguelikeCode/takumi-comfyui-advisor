"""
Takumi Bridge Server API (Refactored)

[Why] To act as the intelligent interface between the User and ComfyUI.
[What] Handles chat requests, resolves intents (Fast Path/AI), and orchestrates workflow loading.
"""

import server
import aiohttp
from aiohttp import web
import json
import os
import sys
import subprocess
from typing import Dict, Any, Optional, Tuple

# ==============================================================================
# [1] Configuration & Constants
# ==============================================================================
class TakumiConfig:
    """Central configuration for paths and AI settings."""
    
    # AI Settings
    OLLAMA_API_URL = "http://localhost:11434/api/generate"
    MODEL_NAME = "gemma2:2b"
    
    # Paths
    BASE_CONFIG_DIR = "/app/config/takumi_meta"
    COMFY_ROOT = "/app/external/ComfyUI"
    CUSTOM_NODES_DIR = os.path.join(COMFY_ROOT, "custom_nodes")

    @staticmethod
    def get_asset_path(rel_path: str) -> str:
        """
        [Why] Search priority: Enterprise > Core
        """
        ent_path = os.path.join(TakumiConfig.BASE_CONFIG_DIR, "enterprise", rel_path)
        if os.path.exists(ent_path):
            return ent_path
        return os.path.join(TakumiConfig.BASE_CONFIG_DIR, "core", rel_path)

# ==============================================================================
# [2] Catalog Manager (The Librarian)
# ==============================================================================
class CatalogManager:
    """Handles loading, validating, and formatting workflow metadata."""

    @staticmethod
    def load_validated_catalog() -> Dict[str, Any]:
        """
        [Why] Loads metadata and filters out unavailable workflows.
        [What] Checks 'dependency_target' against the physical filesystem.
        """
        raw_catalog = {}
        namespaces = ["core", "enterprise"]
        
        # 1. Load Raw JSONs
        for ns in namespaces:
            path = os.path.join(TakumiConfig.BASE_CONFIG_DIR, ns, "entities", "workflows_meta.json")
            if os.path.exists(path):
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        raw_catalog.update(json.load(f))
                except Exception as e:
                    print(f"[Takumi] Error loading {ns} catalog: {e}", file=sys.stderr)

        # 2. Validate Availability (Physical Check)
        valid_catalog = {}
        for key, val in raw_catalog.items():
            target = val.get("dependency_target")
            
            if target:
                # Resolve relative path (custom_nodes or models)
                check_path = os.path.join(TakumiConfig.COMFY_ROOT, target)
                
                # If target does not exist, exclude this workflow
                if not os.path.exists(check_path):
                    continue
            
            valid_catalog[key] = val
            
        return valid_catalog

    @staticmethod
    def build_system_prompt() -> str:
        """
        [Why] Constructs the AI context with the current catalog.
        [What] Injects both 'Logic Data' (for AI) and 'Menu Data' (for Display).
        """
        # Load Base Prompt
        prompt_path = TakumiConfig.get_asset_path("prompts/capabilities.txt")
        if not os.path.exists(prompt_path):
            return "You are a Router. Output JSON only."
        
        with open(prompt_path, 'r', encoding='utf-8') as f:
            base_prompt = f.read()

        # Load Persona (Optional)
        persona_path = TakumiConfig.get_asset_path("prompts/persona.txt")
        persona = ""
        if os.path.exists(persona_path) and "2b" not in TakumiConfig.MODEL_NAME:
             with open(persona_path, 'r', encoding='utf-8') as f:
                persona = f.read()

        # Format Catalog
        catalog = CatalogManager.load_validated_catalog()
        logic_lines = [] # [ID] Name | Tags
        menu_lines = []  # 🔹 Name

        for key, val in catalog.items():
            name = val.get("name", "Unknown")
            tags = ", ".join(val.get("tags", []))
            logic_lines.append(f"[{key}] {name} | Tags: {tags}")
            menu_lines.append(f"🔹 {name}")

        # Injection
        full_prompt = base_prompt.replace("{{WORKFLOW_CATALOG}}", "\n".join(logic_lines))
        full_prompt = full_prompt.replace("{{WORKFLOW_MENU}}", "\n".join(menu_lines))

        return f"{persona}\n\n{full_prompt}" if persona else full_prompt

# ==============================================================================
# [3] Intent Resolver (The Brain)
# ==============================================================================
class IntentResolver:
    """Decides whether to use Fast Path (Regex/Match) or AI Inference."""

    @staticmethod
    async def resolve(user_input: str) -> Dict[str, Any]:
        
        # Strategy A: Fast Path (Direct Name Match)
        # [Why] Bypass AI for deterministic menu selections (Speed & Accuracy).
        catalog = CatalogManager.load_validated_catalog()
        clean_input = user_input.replace("🔹", "").strip().lower()

        for wf_id, meta in catalog.items():
            wf_name = meta.get("name", "").strip().lower()
            if clean_input == wf_name:
                print(f">>> [Takumi] Fast Path Triggered: {wf_id}")
                return {
                    "action": "load_workflow",
                    "target_id": wf_id,
                    "params": {}
                }

        # Strategy B: AI Inference (Ollama)
        # [Why] Handle vague requests or complex parameters.
        return await IntentResolver._query_ollama(user_input)

    @staticmethod
    async def _query_ollama(user_input: str) -> Dict[str, Any]:
        system_prompt = CatalogManager.build_system_prompt()
        payload = {
            "model": TakumiConfig.MODEL_NAME,
            "prompt": user_input,
            "system": system_prompt,
            "stream": False,
            "format": "json"
        }

        print(f">>> [Takumi] AI Query: {user_input}", file=sys.stderr)
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(TakumiConfig.OLLAMA_API_URL, json=payload) as resp:
                    if resp.status == 404:
                        await IntentResolver._pull_model()
                        return await IntentResolver._query_ollama(user_input) # Retry
                    
                    if resp.status != 200:
                        return {"response": f"AI Error: {resp.status}"}
                    
                    data = await resp.json()
                    return IntentResolver._parse_ai_response(data.get("response", ""))
                    
        except Exception as e:
            return {"response": f"Connection Error: {e}"}

    @staticmethod
    def _parse_ai_response(raw_text: str) -> Dict[str, Any]:
        try:
            # Clean markdown code blocks
            clean_text = raw_text.strip()
            if clean_text.startswith("```json"): clean_text = clean_text[7:]
            if clean_text.endswith("```"): clean_text = clean_text[:-3]
            return json.loads(clean_text)
        except json.JSONDecodeError:
            return {"response": raw_text}

    @staticmethod
    async def _pull_model():
        print(f">>> [Takumi] Pulling model {TakumiConfig.MODEL_NAME}...", file=sys.stderr)
        subprocess.run(["ollama", "pull", TakumiConfig.MODEL_NAME], check=True)

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
        
        # Load JSON File
        if not os.path.exists(path):
            return {"type": "text", "response": f"File not found: {path}"}
            
        try:
            with open(path, 'r', encoding='utf-8') as f:
                workflow = json.load(f)
        except Exception as e:
            return {"type": "text", "response": f"Invalid JSON: {e}"}

        # Inject Parameters (e.g., Prompt replacement)
        params = action_data.get("params", {})
        mapping = meta.get("mapping", {})
        injected = []

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

        # Response Construction
        msg = f"Loaded: **{meta.get('name')}**"
        if injected: msg += f"\n({', '.join(injected)})"

        return {
            "type": "action",
            "message": msg,
            "workflow": workflow
        }

# ==============================================================================
# [5] Route Handler (The Controller)
# ==============================================================================
@server.PromptServer.instance.routes.post("/takumi/chat")
async def chat_handler(request):
    try:
        req_data = await request.json()
        user_prompt = req_data.get("prompt", "").strip()
        
        if not user_prompt:
            return web.json_response({"type": "text", "response": "..."})

        # 1. Resolve Intent (Fast Path or AI)
        ai_result = await IntentResolver.resolve(user_prompt)

        # 2. Execute Action if present
        if ai_result.get("action") == "load_workflow":
            response_payload = WorkflowExecutor.execute(ai_result)
            return web.json_response(response_payload)

        # 3. Return Text Response
        response_text = ai_result.get("response", str(ai_result))
        return web.json_response({"type": "text", "response": response_text})

    except Exception as e:
        print(f"[Takumi] Critical Error: {e}", file=sys.stderr)
        return web.json_response({"type": "text", "response": "Internal Server Error."})