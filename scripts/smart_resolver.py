"""
Takumi Smart Resolver v2.0 (Refactored)
[Why] Autonomous dependency resolution agent for ComfyUI.
[What] Scans nodes, applies knowledge-base rules, resolves conflicts, and reports telemetry.
"""

import os
import sys
import json
import glob
import subprocess
import datetime
import uuid
import platform
import urllib.request
import gzip
import base64
import re

# --- Configuration ---
class Config:
    COMFY_PATH = "/app/external/ComfyUI"
    CUSTOM_NODES_PATH = os.path.join(COMFY_PATH, "custom_nodes")
    # Output path for the frozen recipe
    RECIPE_OUTPUT_PATH = "/app/cache/recipes"
    # Knowledge Base path
    RULES_PATH = "/app/config/takumi_meta/core/infra/dependency_rules.json"
    # Telemetry Endpoint
    API_URL = "https://h9qf4nsc0i.execute-api.ap-northeast-1.amazonaws.com/logs"
    # User Agent
    USER_AGENT = "Takumi-SmartResolver/2.0"

class Utils:
    @staticmethod
    def normalize_name(name):
        """Normalizes package names (e.g. 'Diffusers' -> 'diffusers')."""
        return name.strip().lower().replace("-", "_")

    @staticmethod
    def get_package_name(req_string):
        """Extracts package name from requirement string (handles extras like 'pkg[opt]')."""
        # Split by comparison operators, brackets, semicolons
        parts = re.split(r'[<>=!\[;]', req_string.strip())
        return Utils.normalize_name(parts[0])

class Telemetry:
    """Handles data transmission to AWS."""
    @staticmethod
    def send(data):
        print("📡 [Telemetry] Uploading session data...")
        try:
            json_str = json.dumps(data, ensure_ascii=False)
            compressed = gzip.compress(json_str.encode('utf-8'))
            b64_body = base64.b64encode(compressed).decode('utf-8')
            
            payload = json.dumps({
                "log_type": "dependency_graph",
                "is_compressed": True,
                "body": b64_body
            }).encode('utf-8')

            req = urllib.request.Request(Config.API_URL, data=payload, headers={
                'Content-Type': 'application/json',
                'User-Agent': Config.USER_AGENT
            })
            with urllib.request.urlopen(req) as res:
                print(f"   -> Upload success. ID: {res.read().decode('utf-8')}")
        except Exception as e:
            print(f"   -> Upload failed: {e}")

class KnowledgeBase:
    """Loads external rules."""
    def __init__(self):
        self.node_rules = {}
        self.strategies = {}
        self.conflict_matrix = []
        self._load()

    def _load(self):
        if os.path.exists(Config.RULES_PATH):
            try:
                with open(Config.RULES_PATH, 'r') as f:
                    data = json.load(f)
                    self.node_rules = data.get("node_specific_rules", {})
                    self.strategies = data.get("strategies", {})
                    self.conflict_matrix = data.get("conflict_matrix", [])
                    print(f"📘 [Knowledge] Loaded rules from {os.path.basename(Config.RULES_PATH)}")
            except Exception as e:
                print(f"⚠️  Failed to load rules: {e}")

class DependencyAgent:
    def __init__(self):
        self.session_id = str(uuid.uuid4())
        self.timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        self.kb = KnowledgeBase()
        self.input_manifest = {} 
        self.trials = []
        self.status = "pending"

    def scan_environment(self):
        """Scans custom nodes and applies node-specific injections."""
        print("🔍 [Agent] Scanning custom nodes...")
        
        if not os.path.exists(Config.CUSTOM_NODES_PATH):
            return

        for root, _, files in os.walk(Config.CUSTOM_NODES_PATH):
            node_name = os.path.basename(root)
            if node_name.startswith("."): continue

            node_deps = []
            
            # 1. Apply Knowledge Base Rules
            rule = self.kb.node_rules.get(node_name)
            target_files = ["requirements.txt"]
            
            if rule:
                print(f"   -> ⚡ Applying rule for {node_name}")
                if "extra_files" in rule:
                    target_files.extend(rule["extra_files"])
                if "inject" in rule:
                    node_deps.extend(rule["inject"])

            # 2. File Scan
            for filename in target_files:
                if filename in files:
                    file_path = os.path.join(root, filename)
                    try:
                        with open(file_path, 'r', encoding='utf-8') as f:
                            deps = [line.strip() for line in f if line.strip() and not line.startswith('#')]
                            node_deps.extend(deps)
                    except Exception:
                        pass

            if node_deps:
                self.input_manifest[node_name] = node_deps

        print(f"   -> Found {len(self.input_manifest)} nodes with dependencies.")

    def execute_strategy(self, strategy_name, constraints=None, override_packages=None):
        """Attempts an installation strategy using uv."""
        print(f"\n🤖 [Agent] Executing Strategy: {strategy_name}")
        
        env = os.environ.copy()
        env["UV_LINK_MODE"] = "copy"
        
        # Build Requirements List
        final_reqs = []
        
        # Prepare Override Set
        normalized_overrides = set()
        if override_packages:
            normalized_overrides = {Utils.normalize_name(p) for p in override_packages}

        # Merge from Manifest
        for deps in self.input_manifest.values():
            for req in deps:
                if override_packages:
                    pkg_name = Utils.get_package_name(req)
                    if pkg_name in normalized_overrides:
                        continue 
                final_reqs.append(req)

        # Apply Conflict Matrix
        final_reqs = self.apply_conflict_matrix(final_reqs)
            
        # Add Constraints
        if constraints:
            print(f"   -> Applying constraints ({len(constraints)} packages)")
            final_reqs.extend(constraints)

        # Write temp file
        temp_req = f"/tmp/req_{self.session_id}.txt"
        with open(temp_req, 'w') as f:
            f.write("\n".join(final_reqs))

        # Execute uv
        start_time = datetime.datetime.now()
        cmd = ["uv", "pip", "install", "--python", sys.executable, "-r", temp_req]
        
        process = subprocess.run(cmd, capture_output=True, text=True, env=env)
        
        duration = (datetime.datetime.now() - start_time).total_seconds()
        success = (process.returncode == 0)
        
        # Logging & Recording
        self.trials.append({
            "strategy": strategy_name,
            "success": success,
            "duration": duration,
            "log_snippet": process.stderr[-1000:] if process.stderr else process.stdout[-200:]
        })

        if success:
            print("   ✅ Success!")
            return True
        else:
            print("   ❌ Failed.")
            # Show Debug Log
            lines = process.stderr.splitlines()
            if lines:
                print("\n   [DEBUG] Error Log (Last 5 lines):")
                for line in lines[-5:]:
                    print(f"   > {line}")
            return False
        
    def apply_conflict_matrix(self, requirements):
        """
        Applies the Conflict Matrix to purge incompatible packages.
        Returns: Cleaned list of requirements.
        """
        if not self.kb.conflict_matrix:
            return requirements

        print("   ⚖️ [Arbiter] Checking Conflict Matrix...")
        
        # 1. Normalize all inputs for comparison
        req_map = {Utils.get_package_name(r): r for r in requirements}
        active_packages = set(req_map.keys())
        
        # 2. Identify Ban List based on Triggers
        ban_list = set()
        
        for rule in self.kb.conflict_matrix:
            triggers = set(rule.get("trigger", []))
            bans = set(rule.get("ban", []))
            
            # If any trigger package is included in the list
            if not triggers.isdisjoint(active_packages):
                # Determine who is being banned
                ban_list.update(bans)
                print(f"      -> Triggered: {rule.get('description', 'Unknown Rule')}")
                print(f"         (Banning: {bans})")

        # 3. Purge
        final_reqs = []
        for req in requirements:
            pkg_name = Utils.get_package_name(req)
            if pkg_name in ban_list:
                # Only remove if it's on the ban list but not the trigger itself
                # (Unless the trigger itself is on the ban list)
                print(f"      🗑️ Purged: {req}")
                continue
            final_reqs.append(req)
            
        return final_reqs

    def export_recipe(self):
        """Exports the frozen environment as a Takumi Recipe JSON."""
        print("💾 [Agent] Freezing successful environment...")
        os.makedirs(Config.RECIPE_OUTPUT_PATH, exist_ok=True)
        
        # Freeze pip
        freeze = subprocess.check_output([sys.executable, "-m", "pip", "freeze"], text=True)
        components = []
        for line in freeze.splitlines():
            if "==" in line:
                pkg, ver = line.split("==", 1)
                components.append({"type": "pip", "source": pkg, "version": f"=={ver}"})

        # Note: Custom Node linking logic omitted for brevity, focusing on dependencies
        
        recipe = {
            "asset_id": f"takumi-autogen-{self.session_id[:8]}",
            "created_at": self.timestamp,
            "components": components
        }
        
        out_file = os.path.join(Config.RECIPE_OUTPUT_PATH, f"recipe_{self.session_id[:8]}.json")
        with open(out_file, 'w') as f:
            json.dump(recipe, f, indent=2)
        print(f"   -> Saved to: {out_file}")

    def solve(self):
        print("\n⚔️ [Agent] Starting Battle Phase...")

        # Strategy 1: Naive Merge
        if self.execute_strategy("naive_merge"):
            self.status = "success"
            return True

        # Strategy 2: Dictator Mode (Load from Knowledge Base)
        dictator_config = self.kb.strategies.get("dictator_mode", {})
        if dictator_config.get("enabled"):
            print("   -> ⚡ Activating Dictator Mode (Loaded from KB)")
            if self.execute_strategy(
                "dictator_mode", 
                constraints=dictator_config.get("modern_constraints"),
                override_packages=dictator_config.get("override_packages")
            ):
                self.status = "success"
                return True

        self.status = "failed"
        return False

    def finalize(self):
        Telemetry.send({
            "session_id": self.session_id,
            "input_manifest": self.input_manifest,
            "trials": self.trials,
            "final_status": self.status
        })
        
        if self.status == "success":
            self.export_recipe()
            print("\n✨ Dependency Resolution Complete.")
            sys.exit(0)
        else:
            print("\n🔥 Dependency Resolution Failed.")
            sys.exit(1)

if __name__ == "__main__":
    DependencyAgent().scan_environment()
    DependencyAgent().solve()
    DependencyAgent().finalize()