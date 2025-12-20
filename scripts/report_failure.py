# [Why] To collect the status of an installation failure
# [What] Environmental information, error logs, and recipes are collected, anonymized, and sent to AWS.
# [Input] args: log_file_path, recipe_path

import sys
import json
import os
import platform
import urllib.request
import subprocess
from datetime import datetime, timezone

# --- Configuration ---
# API endpoint for the Data Lake
API_URL = "https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"

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

def read_last_logs(log_path, lines=100):
    """[Why] Reads the tail of the log file."""
    if not os.path.exists(log_path):
        return ["Log file not found."]
    
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Read all and take the last N lines (Simple implementation)
            content = f.readlines()
            return [sanitize_path(line.strip()) for line in content[-lines:]]
    except Exception as e:
        return [f"Error reading log: {str(e)}"]

def load_recipe(recipe_path):
    """[Why] Loads the target recipe to understand user intent."""
    if recipe_path and os.path.exists(recipe_path):
        try:
            with open(recipe_path, 'r') as f:
                return json.load(f)
        except Exception:
            return {"error": "Failed to load recipe"}
    return None

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
            print(f">>> [Report] Failure log sent. ID: {response}")
    except Exception as e:
        # Sending failures are handled silently, without disrupting the user experience.
        print(f">>> [Report] Failed to send log (Network issue?): {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python report_failure.py <log_file> [recipe_file]")
        return

    log_file = sys.argv[1]
    recipe_file = sys.argv[2] if len(sys.argv) > 2 else None

    print("\n>>> [Takumi] ⚠️  Installation failed. Gathering diagnostics...")

    payload = {
        "event_type": "install_failure",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "system_info": get_system_info(),
        "error_log": read_last_logs(log_file),
        "target_recipe": load_recipe(recipe_file)
    }

    # Debug: Print summary locally
    # print(json.dumps(payload, indent=2))

    print(">>> [Takumi] Sending anonymous crash report to improve future versions...")
    send_report(payload)

if __name__ == "__main__":
    main()