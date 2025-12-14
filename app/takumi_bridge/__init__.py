"""
Takumi Bridge Node Initialization

[Why] To register the extension with ComfyUI and expose web assets.
[What] Defines the web directory and initializes the server routes.
"""

from . import server

# ==============================================================================
# ComfyUI Node Configuration
# ==============================================================================

# [Why] To serve the frontend assets (JS/CSS/Images) to the browser.
# [What] Points to the './js' directory relative to this file.
WEB_DIRECTORY = "./js"

# [Why] This extension provides a backend API (Bridge), not a processing node.
# [What] Define empty mappings to satisfy ComfyUI's loader requirements.
# [Note] The logic resides in 'server.py' (API) and 'js/takumi.js' (Frontend).
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# [Why] To explicitly define what this module exports.
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]

print(f">>> [TakumiBridge] Loaded. Web extension ready at '{WEB_DIRECTORY}'.")