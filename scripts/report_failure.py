# [Why] To collect the status of an installation failure
# [What] Environmental information, error logs, and recipes are collected, anonymized, and sent to AWS.
# [Input] args: log_file_path, recipe_path

import sys
import json
import os
import platform
import urllib.request
import subprocess
import gzip
import base64
from datetime import datetime, timezone

# --- Configuration ---
API_URL = "https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"

def read_full_log(log_path, max_size=900*1024): # 900KB limit (Leave room for metadata)
    """
    [Why] Reads the log file as much as possible.
    """
    if not os.path.exists(log_path):
        return "Log file not found."
    
    try:
        file_size = os.path.getsize(log_path)
        
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            if file_size > max_size:
                # If the file is too large, read from the end
                f.seek(file_size - max_size)
                content = f.read()
                return "...(truncated)...\n" + sanitize_path(content)
            else:
                return sanitize_path(f.read())
    except Exception as e:
        return f"Error reading log: {str(e)}"

def sanitize_path(text):
    """
    [Why] To protect user privacy by hiding home directory paths.
    [What] Replaces /home/username with /home/<USER>.
    """
    if not text:
        return ""
    try:
        home = os.path.expanduser("~")
        return text.replace(home, "/home/<USER>")
    except Exception:
        return text
    
def get_python_packages():
    """
    [Why] To analyze dependency conflicts (The DNA of the environment).
    [What] Returns the output of 'pip freeze'.
    """
    try:
        # Run pip freeze
        result = subprocess.check_output(
            [sys.executable, "-m", "pip", "freeze"],
            encoding="utf-8",
            stderr=subprocess.DEVNULL
        )
        return result.splitlines()
    except Exception as e:
        return [f"Error getting packages: {str(e)}"]

def get_gpu_info():
    """
    [Why] To correlate errors with hardware constraints (VRAM, CUDA version).
    [What] Runs nvidia-smi if available.
    """
    try:
        # Check if nvidia-smi exists
        subprocess.check_call(["which", "nvidia-smi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # Get simplified GPU info
        result = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"],
            encoding="utf-8",
            stderr=subprocess.DEVNULL
        )
        return result.strip().splitlines()
    except Exception:
        return ["GPU info unavailable (CPU only or nvidia-smi missing)"]

def get_system_info():
    """[Why] Basic OS and Python version info."""
    return {
        "os": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python_version": sys.version.split()[0],
        "gpu_info": get_gpu_info(),       # [New]
        "python_packages": get_python_packages() # [New]
    }

def load_recipe(recipe_path):
    """[Why] Loads the target recipe to understand user intent."""
    if recipe_path and os.path.exists(recipe_path):
        try:
            with open(recipe_path, 'r') as f:
                return json.load(f)
        except Exception:
            return {"error": "Failed to load recipe"}
    return None

def compress_payload(data_dict):
    """
    JSON -> Bytes -> Gzip -> Base64 String
    [Why] To reduce payload size (save bandwidth/tokens).
    """
    # 1. JSON Stringification
    json_str = json.dumps(data_dict, ensure_ascii=False)
    # 2. Gzip compression
    compressed_data = gzip.compress(json_str.encode('utf-8'))
    # 3. Base64 encoding (converted to a string to send in JSON)
    b64_str = base64.b64encode(compressed_data).decode('utf-8')
    return b64_str

def send_report(payload):
    """[Why] Sends the JSON payload to AWS Lambda."""
    try:
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(API_URL, data=data, headers={
            'Content-Type': 'application/json',
            'User-Agent': 'Takumi-Installer/2.0'
        })
        with urllib.request.urlopen(req) as res:
            response = res.read().decode('utf-8')
            print(f">>> [Report] Log sent. ID: {response}")
    except Exception as e:
        # Sending failures are handled silently, without disrupting the user experience.
        print(f">>> [Report] Failed to send log (Network issue?): {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python report_failure.py <log_file> [recipe_file]")
        return

    log_file = sys.argv[1]
    recipe_file = sys.argv[2] if len(sys.argv) > 2 else None

    print("\n>>> [Takumi] 📡 Uploading installation log to Data Lake...")

    payload = {
        "log_type": "install_log", 
        "event_type": "install_failure",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "system_info": get_system_info(),
        "install_log_content": read_full_log(log_file), 
        "target_recipe": load_recipe(recipe_file)
    }

    # Debug: Print summary locally
    # print(json.dumps(payload, indent=2))

    send_report(payload)

if __name__ == "__main__":
    main()