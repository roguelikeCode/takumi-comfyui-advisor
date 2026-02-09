"""
Takumi Brain Interface (v3.0 Microservices Ready)

[Why] To provide a lightweight, dependency-free interface to the local AI (Ollama).
[What] Manages the Ollama server connection and executes inference.
"""

import sys
import json
import urllib.request
import urllib.error
import subprocess
import time
import os
from typing import Optional, Dict, Any

# ==============================================================================
# [1] Configuration
# ==============================================================================
class BrainConfig:
    # Service Endpoint
    # [Fix] Use environment variable for Microservices support
    _raw_host = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
    # Clean up URL (remove /v1 if present for raw API access)
    _base_host = _raw_host.replace("/v1", "").rstrip("/")
    
    API_URL = f"{_base_host}/api/generate"
    MODEL_NAME = "gemma3:4b"

    # Base Paths
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    META_ROOT = os.path.join(BASE_DIR, "config", "takumi_meta")

    @staticmethod
    def get_prompt_path(filename="prompts/capabilities.txt"):
        ent_path = os.path.join(BrainConfig.META_ROOT, "enterprise", filename)
        if os.path.exists(ent_path):
            return ent_path
        return os.path.join(BrainConfig.META_ROOT, "core", filename)

# ==============================================================================
# [2] Infrastructure Manager (Ollama Control)
# ==============================================================================
class OllamaManager:
    """Manages the connection to the AI server."""

    @staticmethod
    def ensure_server_running() -> None:
        """
        [Why] To guarantee the AI server is available.
        [What] Checks connection. In Microservices mode, we DO NOT spawn the server locally.
        """
        
        # Check if we are pointing to an external service
        if "127.0.0.1" not in BrainConfig.API_URL and "localhost" not in BrainConfig.API_URL:
            # External Mode: Just check connectivity, don't start anything.
            if not OllamaManager._is_server_reachable():
                print(f">>> [Brain] Warning: External Brain at {BrainConfig.API_URL} is unreachable.", file=sys.stderr)
            return

        # Local Mode: Start server if needed
        if OllamaManager._is_server_reachable():
            return

        print(">>> [Brain] Starting Local Ollama server...", file=sys.stderr)
        try:
            subprocess.Popen(
                ["ollama", "serve"], 
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL
            )
            for _ in range(10):
                if OllamaManager._is_server_reachable():
                    return
                time.sleep(1)
            raise ConnectionError("Local Ollama server failed to start.")
        except FileNotFoundError:
            print(">>> [Brain] Critical: 'ollama' command not found.", file=sys.stderr)

    @staticmethod
    def _is_server_reachable() -> bool:
        """[What] Pings the Ollama API root."""
        try:
            base_url = BrainConfig.API_URL.replace("/api/generate", "")
            with urllib.request.urlopen(base_url, timeout=1) as _:
                return True
        except Exception:
            return False

    @staticmethod
    def pull_model(model_name: str) -> bool:
        """
        [Why] To handle 'Model not found' errors.
        [What] Executes 'ollama pull'. Works remotely if OLLAMA_HOST is set.
        """
        print(f">>> [Brain] Model '{model_name}' missing. Pulling...", file=sys.stderr)
        try:
            # Pass environment variable to subprocess to target remote host
            env = os.environ.copy()
            subprocess.run(["ollama", "pull", model_name], check=True, env=env)
            return True
        except subprocess.CalledProcessError:
            print(f">>> [Brain] Failed to pull model '{model_name}'.", file=sys.stderr)
            return False

# ==============================================================================
# [3] Inference Engine (The Mind)
# ==============================================================================
class BrainEngine:
    @staticmethod
    def load_system_prompt(prompt_type="debugger") -> str:
        """
        [Why] Switch personas based on context.
        [Input] prompt_type: 'debugger' (default) or 'capabilities'
        """
        filename = f"prompts/{prompt_type}.txt"
        prompt_path = BrainConfig.get_prompt_path(filename)
        
        if os.path.exists(prompt_path):
            try:
                with open(prompt_path, 'r', encoding='utf-8') as f:
                    return f.read()
            except Exception:
                pass
        
        # Fallback for Debugger
        return "You are a Linux System Administrator. Analyze the error log and provide a concise solution."

    @staticmethod
    def query(user_prompt: str, context: Optional[str] = None) -> str:
        # Debugger persona
        system_prompt = BrainEngine.load_system_prompt("debugger")
        
        full_prompt = user_prompt
        if context:
            # [Fix] Get the LAST 2000 chars (Tail), not the first. Errors are at the end.
            safe_context = context[-2000:] 
            full_prompt = f"{user_prompt}\n\n[Error Log (Last 2000 chars)]\n{safe_context}"

        payload = {
            "model": BrainConfig.MODEL_NAME,
            "prompt": full_prompt,
            "system": system_prompt,
            "stream": False
        }
        return BrainEngine._send_request(payload)

    @staticmethod
    def _send_request(payload: Dict[str, Any], retry: bool = True) -> str:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            BrainConfig.API_URL, 
            data=data, 
            headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode("utf-8"))
                return result.get("response", "")
        except urllib.error.HTTPError as e:
            if e.code == 404 and retry:
                if OllamaManager.pull_model(payload["model"]):
                    return BrainEngine._send_request(payload, retry=False)
            return f"AI Error: {e}"
        except Exception as e:
            return f"AI Connection Error: {e}"

# ==============================================================================
# Main Entry Point
# ==============================================================================
def main():
    if len(sys.argv) < 2:
        print("Usage: python brain.py <prompt> [context]")
        sys.exit(1)

    prompt = sys.argv[1]
    error_context = sys.argv[2] if len(sys.argv) > 2 else None

    OllamaManager.ensure_server_running()
    print(BrainEngine.query(prompt, error_context))

if __name__ == "__main__":
    main()