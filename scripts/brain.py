"""
Takumi Brain Interface (v3.1 Microservices Ready)

[Why] To provide a lightweight, dependency-free HTTP interface to the local AI (Ollama).
[What] Manages the Ollama server connection, executes inference, and aggressively frees VRAM.
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
# [1] Configuration & Constants
# ==============================================================================
class BrainConfig:
    """Central configuration for the AI Inference Engine."""
    
    # Service Endpoint (Microservices compatible)
    _raw_host: str = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
    # Sanitize URL by stripping the '/v1' suffix to ensure raw API access
    _base_host: str = _raw_host.replace("/v1", "").rstrip("/")
    
    API_URL: str = f"{_base_host}/api/generate"
    MODEL_NAME: str = "gemma3:4b"

    # Base Path Resolution
    BASE_DIR: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # Base Path Resolution
    META_ROOT: str = "/app/external/takumi-event-store"

    @classmethod
    def get_prompt_path(cls, filename: str = "prompts/capabilities.txt") -> str:
        """
        [Why] To resolve the absolute path of prompt definitions from the flat Event Store.
        """
        return os.path.join(cls.META_ROOT, filename)

# ==============================================================================
# [2] Infrastructure Manager (Ollama Control)
# ==============================================================================
class OllamaManager:
    """Manages the lifecycle and connection state of the AI server."""

    @staticmethod
    def ensure_server_running() -> None:
        """
        [Why] To guarantee the AI server is available for inference.
        [What] Verifies connectivity. In Microservices mode, avoids spawning a local instance.
        """
        is_remote = "127.0.0.1" not in BrainConfig.API_URL and "localhost" not in BrainConfig.API_URL

        if OllamaManager._is_server_reachable():
            return

        if is_remote:
            print(f">>> [Brain] Warning: External Brain at {BrainConfig.API_URL} is unreachable.", file=sys.stderr)
            return

        print(">>> [Brain] Starting Local Ollama server in background...", file=sys.stderr)
        try:
            subprocess.Popen(["ollama", "serve"], 
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL
            )
            for _ in range(10):
                if OllamaManager._is_server_reachable():
                    return
                time.sleep(1)
            raise ConnectionError("Local Ollama server failed to ignite.")
        except FileNotFoundError:
            print(">>> [Brain] Critical: 'ollama' command not found in system path.", file=sys.stderr)

    @staticmethod
    def _is_server_reachable() -> bool:
        """[What] Pings the root endpoint of the Ollama API to verify availability."""
        try:
            base_url = BrainConfig.API_URL.replace("/api/generate", "")
            with urllib.request.urlopen(base_url, timeout=1) as _:
                return True
        except Exception:
            return False

    @staticmethod
    def pull_model(model_name: str) -> bool:
        """
        [Why] To handle 'Model not found' (404) states automatically.
        [What] Executes 'ollama pull' via subprocess. Works remotely if OLLAMA_HOST is set.
        """
        print(f"\n>>>[Brain] 🧠 Initial download requested for AI model '{model_name}'.")
        print(f">>> [Brain] ⏳ This process may take a few minutes depending on your network. Please wait...\n", file=sys.stderr)
        try:
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
    """Constructs prompts and executes HTTP requests to the LLM."""

    @staticmethod
    def load_system_prompt(prompt_type: str = "debugger") -> str:
        """
        [Why] To switch the AI persona based on the execution context.
        """
        filename = f"prompts/{prompt_type}.txt"
        prompt_path = BrainConfig.get_prompt_path(filename)
        
        if os.path.exists(prompt_path):
            try:
                with open(prompt_path, 'r', encoding='utf-8') as f:
                    return f.read()
            except Exception:
                pass
        
        # Fallback directive
        return "You are an expert Systems Engineer. Analyze the error log and provide a concise, actionable solution."

    @staticmethod
    def query(user_prompt: str, context: Optional[str] = None) -> str:
        """
        [Why] The primary interface for asking questions to the AI.
        [What] Constructs the payload and triggers the request.
        """
        system_prompt = BrainEngine.load_system_prompt("debugger")
        full_prompt = user_prompt
        
        if context:
            # [Why] Extract only the trailing 2000 characters where the actual error stack typically resides.
            safe_context = context[-2000:] 
            full_prompt = f"{user_prompt}\n\n[Error Log (Last 2000 chars)]\n{safe_context}"

        payload = {
            "model": BrainConfig.MODEL_NAME,
            "prompt": full_prompt,
            "system": system_prompt,
            "stream": False,
            # [Optimization] Unload from VRAM aggressively after 20 seconds to maximize resources for ComfyUI.
            "keep_alive": "20s" 
        }
        return BrainEngine._send_request(payload)

    @staticmethod
    def _send_request(payload: Dict[str, Any], retry: bool = True) -> str:
        """[What] Transmits the JSON payload and handles the HTTP response."""
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
            return f"AI Error: HTTP {e.code} - {e.reason}"
        except Exception as e:
            return f"AI Connection Error: {str(e)}"

# ==============================================================================
# Main Entry Point
# ==============================================================================
def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python brain.py <prompt> [context]")
        sys.exit(1)

    prompt = sys.argv[1]
    error_context = sys.argv[2] if len(sys.argv) > 2 else None

    OllamaManager.ensure_server_running()
    print(BrainEngine.query(prompt, error_context))

if __name__ == "__main__":
    main()