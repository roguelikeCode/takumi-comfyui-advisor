"""
Workflow Inspector Tool

[Why] To identify Node IDs and Class Types within a workflow JSON to assist in metadata creation.
[What] Loads the specified workflow JSON file and displays a readable list of nodes and their widgets.
[Input] (Optional) Path to the workflow JSON file. Defaults to 'app/assets/workflows/magic_clothing_v1.json'.
"""

import json
import sys
import os

def main():
    # Default target file (can be overridden by argument)
    file_path = "app/assets/workflows/magic_clothing_v1.json"
    
    # Check if an argument is provided
    if len(sys.argv) > 1:
        file_path = sys.argv[1]

    # Validate path
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found at '{file_path}'")
        print("Usage: python inspect_workflow.py [path/to/workflow.json]")
        return

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        print(f"🔍 Analyzing: {file_path}")
        print("-" * 80)
        print(f"{'ID':<5} | {'Class Type':<35} | {'Title / Widgets'}")
        print("-" * 80)

        nodes = data.get("nodes", [])
        for node in nodes:
            node_id = node.get("id")
            class_type = node.get("type")
            # Try to get the display title or fall back to class type
            title = node.get("properties", {}).get("Node name for S&R") or node.get("title") or class_type
            
            # Preview widget values (truncate if too long)
            widgets = node.get("widgets_values", [])
            widgets_str = str(widgets)
            if len(widgets_str) > 60:
                widgets_str = widgets_str[:57] + "..."
            
            print(f"{node_id:<5} | {class_type:<35} | {title}")
            print(f"      > Widgets: {widgets_str}")
            print("-" * 80)

    except json.JSONDecodeError:
        print(f"❌ Error: Failed to parse JSON. Please check if '{file_path}' is a valid JSON file.")
    except Exception as e:
        print(f"❌ Unexpected Error: {str(e)}")

if __name__ == "__main__":
    main()