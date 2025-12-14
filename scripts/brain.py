"""
Takumi Brain Interface

[Why] To provide a lightweight, dependency-free interface to the local AI (Ollama).
[What] Manages the Ollama server process, handles model downloading, and executes inference.
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
    API_URL = "http://localhost:11434/api/generate"
    
    # Model Selection
    MODEL_NAME = "gemma3"
    
    # Paths
    # [Note] Relative path from this script to the config file
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    SYSTEM_PROMPT_PATH = os.path.join(BASE_DIR, "app", "config", "takumi_meta", "prompts", "system_prompt.txt")

# ==============================================================================
# [2] Infrastructure Manager (Ollama Control)
# ==============================================================================
class OllamaManager:
    """Manages the lifecycle of the local AI server and models."""

    @staticmethod
    def ensure_server_running() -> None:
        """
        [Why] To guarantee the AI server is available before making requests.
        [What] Checks connection; if failed, starts 'ollama serve' in background.
        """
        if OllamaManager._is_server_reachable():
            return

        print(">>> [Brain] Starting Ollama server...", file=sys.stderr)
        try:
            subprocess.Popen(
                ["ollama", "serve"], 
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL
            )
            # Wait for server to wake up
            for _ in range(10):
                if OllamaManager._is_server_reachable():
                    return
                time.sleep(1)
            
            raise ConnectionError("Ollama server failed to start within timeout.")
        except FileNotFoundError:
            print(">>> [Brain] Critical: 'ollama' command not found. Is it installed?", file=sys.stderr)
            sys.exit(1)

    @staticmethod
    def _is_server_reachable() -> bool:
        """[What] Pings the Ollama API root."""
        try:
            # Check root endpoint (usually returns 200 OK)
            base_url = BrainConfig.API_URL.replace("/api/generate", "")
            with urllib.request.urlopen(base_url, timeout=1) as _:
                return True
        except (urllib.error.URLError, ConnectionRefusedError):
            return False
        except Exception:
            return False

    @staticmethod
    def pull_model(model_name: str) -> bool:
        """
        [Why] To handle 'Model not found' errors automatically.
        [What] Executes 'ollama pull' as a blocking subprocess.
        """
        print(f">>> [Brain] Model '{model_name}' not found. Pulling now... (This may take a while)", file=sys.stderr)
        try:
            subprocess.run(["ollama", "pull", model_name], check=True)
            print(f">>> [Brain] Model '{model_name}' ready.", file=sys.stderr)
            return True
        except subprocess.CalledProcessError:
            print(f">>> [Brain] Failed to pull model '{model_name}'.", file=sys.stderr)
            return False

# ==============================================================================
# [3] Inference Engine (The Mind)
# ==============================================================================
class BrainEngine:
    """Handles prompt loading and query execution."""

    @staticmethod
    def load_system_prompt() -> str:
        """
        [Why] To inject the Takumi persona and guidelines.
        [What] Reads from external text file, returns fallback if missing.
        """
        if os.path.exists(BrainConfig.SYSTEM_PROMPT_PATH):
            try:
                with open(BrainConfig.SYSTEM_PROMPT_PATH, 'r', encoding='utf-8') as f:
                    return f.read()
            except Exception as e:
                print(f">>> [Brain] Warning: Failed to read system prompt: {e}", file=sys.stderr)
        
        # Fallback Persona
        return "You are Takumi, a helpful AI assistant for troubleshooting."

    @staticmethod
    def query(user_prompt: str, context: Optional[str] = None) -> str:
        """
        [Why] To get an answer from the AI.
        [What] Sends POST request to Ollama, handles 404 retry logic.
        [Input] user_prompt: Main question, context: Optional error logs etc.
        """
        system_prompt = BrainEngine.load_system_prompt()
        
        # Combine inputs if context is provided
        full_prompt = user_prompt
        if context:
            full_prompt = f"{user_prompt}\n\n[Context Info]\n{context}"

        payload = {
            "model": BrainConfig.MODEL_NAME,
            "prompt": full_prompt,
            "system": system_prompt,
            "stream": False
        }

        return BrainEngine._send_request(payload)

    @staticmethod
    def _send_request(payload: Dict[str, Any], retry: bool = True) -> str:
        """[What] Internal method to execute HTTP request with retry logic."""
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
            # Handle Model Missing (404)
            if e.code == 404 and retry:
                if OllamaManager.pull_model(payload["model"]):
                    # Retry once after pulling
                    return BrainEngine._send_request(payload, retry=False)
            return f"AI Error: {e}"
            
        except Exception as e:
            return f"AI Connection Error: {e}"

# ==============================================================================
# Main Entry Point
# ==============================================================================
def main():
    # Argument Validation
    if len(sys.argv) < 2:
        print("Usage: python brain.py <prompt> [optional_error_context]")
        sys.exit(1)

    prompt = sys.argv[1]
    error_context = sys.argv[2] if len(sys.argv) > 2 else None

    # 1. Ensure Infrastructure
    OllamaManager.ensure_server_running()
    
    # 2. Execute Inference
    response = BrainEngine.query(prompt, error_context)
    
    # 3. Output Result (Standard Output for shell capture)
    print(response)

if __name__ == "__main__":
    main()