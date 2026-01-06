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

# [Configuration]
COMFY_PATH = "/app/external/ComfyUI" 
CUSTOM_NODES_PATH = os.path.join(COMFY_PATH, "custom_nodes")
REPORT_PATH = "/app/logs/resolver_report.json"

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
        print(f"➡️  Resolving: {node_name}")
        
        entry = {
            "node_name": node_name,
            "file_path": req_file,
            "status": "pending",
            "error_log": "",
            "timestamp": datetime.datetime.now().isoformat()
        }

        try:
            # Run installation
            result = subprocess.run(
                [sys.executable, "-m", "uv", "pip", "install", "-r", req_file],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                print(f"   ✅ Resolved")
                entry["status"] = "success"
                success_count += 1
            else:
                print(f"   ⚠️  Conflict/Error Detected")
                entry["status"] = "failed"
                # Keep last 1000 chars for analysis
                entry["error_log"] = result.stderr[-1000:] if result.stderr else "Unknown Error"
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

def main():
    print(">>> 🛡️  Starting Takumi Resolver...")
    reqs = get_all_requirements()
    if reqs:
        results, s_count, f_count = install_and_record(reqs)
        save_report(results, s_count, f_count)
    else:
        print("No targets found. Environment is clean.")

if __name__ == "__main__":
    main()