"""
Takumi Resolver: Dependency Conflict Solver
[Why] To discover missing dependencies by aggressively installing everything defined in custom nodes.
[What] Scans custom_nodes, merges requirements.txt, runs pip install and generates a 'resolver_report'.
"""

import os
import sys
import subprocess
import json
import datetime
import platform
import urllib.request
import gzip
import base64

# --- Configuration ---
COMFY_PATH = "/app/external/ComfyUI" 
CUSTOM_NODES_PATH = os.path.join(COMFY_PATH, "custom_nodes")
REPORT_PATH = "/app/logs/resolver_report.json"
API_URL = "https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"

def get_all_requirements():
    req_files = []
    print(f"🔍 [Resolver] Scanning {CUSTOM_NODES_PATH}...")
    
    if not os.path.exists(CUSTOM_NODES_PATH):
        print(f"❌ Error: Directory not found: {CUSTOM_NODES_PATH}")
        return []

    for root, dirs, files in os.walk(CUSTOM_NODES_PATH):
        for file in files:
            if file == "requirements.txt":
                full_path = os.path.join(root, file)
                req_files.append(full_path)
    
    # [Deterministic] Sort alphabetically
    return sorted(req_files)

def install_and_record(req_files):
    results = []
    success_count = 0
    fail_count = 0

    print(f"📦 Found {len(req_files)} dependency targets.")

    for req_file in req_files:
        node_name = os.path.basename(os.path.dirname(req_file))
        print(f"\n➡️  Resolving: {node_name}")
        
        entry = {
            "node_name": node_name,
            "file_path": req_file,
            "status": "pending",
            "error_log": "",
            "timestamp": datetime.datetime.now().isoformat()
        }

        # Real-time output + Log Capture
        captured_log = []
        try:
            # Get the currently running Python path (e.g. /home/takumi/.conda/envs/data_gen_env/bin/python)
            current_python = sys.executable

            # 1. Start Process
            # Remove '--system' and instead pin the target with '--python'
            process = subprocess.Popen(
                ["uv", "pip", "install", "--python", current_python, "-r", req_file],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            # 2. Stream output
            # Read, display, and save the running log line by line
            for line in process.stdout:
                print(f"   {line.strip()}") # Screen display (indented)
                captured_log.append(line)   # Log storage

            # 3. Wait for finish
            process.wait()

            if process.returncode == 0:
                print(f"   ✅ {node_name}: Resolved")
                entry["status"] = "success"
                success_count += 1
            else:
                print(f"   ⚠️  {node_name}: Failed")
                entry["status"] = "failed"
                # Combine and save all logs
                entry["error_log"] = "".join(captured_log)
                fail_count += 1

        except Exception as e:
            print(f"   🔥 Exception: {str(e)}")
            entry["status"] = "error"
            entry["error_log"] = str(e)
            fail_count += 1
        
        results.append(entry)

    return results, success_count, fail_count

def save_report(results, success, fail):
    report_data = {
        "log_type": "resolver_report",
        "meta": {
            "tool": "Takumi Resolver v1.0",
            "generated_at": datetime.datetime.now().isoformat(),
            "python_version": sys.version,
            "platform": platform.platform(),
            "total_targets": len(results),
            "success_count": success,
            "fail_count": fail
        },
        "details": results
    }

    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)

    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        json.dump(report_data, f, indent=2, ensure_ascii=False)
    
    print("-" * 40)
    print(f"📄 Report saved to: {REPORT_PATH}")
    print(f"📊 Summary: {success} Resolved / {fail} Issues Found")

def compress_payload(data_dict):
    json_str = json.dumps(data_dict, ensure_ascii=False)
    compressed_data = gzip.compress(json_str.encode('utf-8'))
    b64_str = base64.b64encode(compressed_data).decode('utf-8')
    return b64_str

def send_report(report_data):
    print("📡 Uploading resolver report...")
    try:
        compressed_body = compress_payload(report_data)
        
        wrapper = {
            "is_compressed": True,
            "log_type": "resolver_report", # Explicitly specified
            "body": compressed_body
        }
        
        data = json.dumps(wrapper).encode('utf-8')
        req = urllib.request.Request(API_URL, data=data, headers={
            'Content-Type': 'application/json',
            'User-Agent': 'Takumi-Resolver/1.0'
        })
        
        with urllib.request.urlopen(req) as res:
            print(f"   -> Upload success. Status: {res.status}")
            
    except Exception as e:
        print(f"   -> Upload failed: {e}")

def main():
    print(">>> 🛡️  Starting Takumi Resolver...")
    
    # 1. Run Diagnostics
    reqs = get_all_requirements()
    if reqs:
        results, s_count, f_count = install_and_record(reqs)
    else:
        results, s_count, f_count = ([], 0, 0)
        print("No targets found. Environment is clean.")

    # 2. Report Data Creation
    report_data = {
        "log_type": "resolver_report", # Also include it for raw data
        "meta": {
            "tool": "Takumi Resolver v1.0",
            "generated_at": datetime.datetime.now().isoformat(),
            "python_version": sys.version,
            "platform": platform.platform(),
            "total_targets": len(results),
            "success_count": s_count,
            "fail_count": f_count
        },
        "details": results
    }

    # 3. Local Storage
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        json.dump(report_data, f, indent=2, ensure_ascii=False)
    
    print("-" * 40)
    print(f"📄 Report saved to: {REPORT_PATH}")
    print(f"📊 Summary: {s_count} Resolved / {f_count} Issues Found")

    # 4. Cloud Transmission
    send_report(report_data)

if __name__ == "__main__":
    main()