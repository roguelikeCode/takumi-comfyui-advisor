# Takumi ComfyUI Advisor

> **Stop Debugging. Start Creating.**
> The AI-Powered Concierge that saves you from Dependency Hell.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Conda](https://img.shields.io/badge/conda-%2344A833.svg?style=flat&logo=anaconda&logoColor=white)](https://docs.conda.io/)
[![Python 3.10 | 3.11 | 3.12](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12-blue)](https://www.python.org/)

---

## The Problem: "Creation Stops at Installation"

ComfyUI has revolutionized AI art, but the path to using it is paved with frustration.
Especially for creators on Windows, the reality is harsh:

*   **No one to talk to:** "The programmer is a Mac user and doesn't understand my Windows errors."
*   **Dependency hell:** "Why does NumPy break with `IMPORT FAILED` when I include other custom nodes?"
*   **C++ Build Nightmares:** `insightface` or `onnxruntime` failing because you don't have Visual Studio Build Tools installed.
*   **Version Mismatch:** "It works on my friend's PC, but crashes on my RTX 3090."
*   **Silent Failures:** PyTorch silently falling back to CPU mode, making rendering painfully slow.

Instead of creating art, you spend days debugging Python errors. **This ends today.**

---

## The Solution: "Takumi"

**Takumi ComfyUI Advisor** stands as a game-changer for creators looking to generate sophisticated AI art without getting bogged down by the intricacies of environment setup.

Takumi simplifies the **physical reality** of AI environments. By encapsulating complex dependencies (Conda, CUDA, C++, Python libraries) into a reproducible "Recipe," Takumi ensures that **what runs on the server runs on your machine.**

### Why Takumi?

1.  **🛡️ Bulletproof Isolation (No more "It works on my machine")**
    Takumi runs inside **Docker**. It doesn't touch your system Python, doesn't conflict with your other apps, and doesn't require you to install complex C++ build tools (e.g., CMake) on Windows.

2.  **✨ One-Command Setup**
    Forget about manually installing 20 different requirements.
    Just type `make install`. Takumi handles Conda, CUDA, PyTorch, and all Custom Nodes automatically.

3.  **🤖 AI Concierge (Yamato_Watase)**
    Built-in LLM (Gemma 3) monitors your workflow. If an error occurs, Takumi explains it in plain language and guides you to the solution.

4.  **🧩 Verified Use-Cases (Recipes)**
    We don't just give you ComfyUI; we give you **"Environments that Work."**
    *   👗 **MagicClothing:** Virtual Try-On environment (Fixed Diffusers/Transformers versions).
    *   🎥 **AnimateDiff:** AI Video generation environment (FFmpeg/Audio enabled).

5.  **📦 Asset Manager**
    Modern AI models require complex combinations of Checkpoints, VAEs, Clips, and Motion Modules. Takumi's "Asset Manager" downloads and links them automatically, solving the fragmented model problem.

---

## ⚡ Quick Start

### Prerequisites
*   **Docker Desktop** (or Rancher Desktop / Podman)
*   **NVIDIA GPU** (Drivers installed)
*   **Git**

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/roguelikeCode/takumi-comfyui-advisor.git
cd takumi-comfyui-advisor

# 2. Build & Install (The Magic Command)
# Select your desired use-case number from the menu (e.g., AnimateDiff)
make install

# 3. Run
make run
```

Access ComfyUI at **http://localhost:8188**

---

## Features

### Takumi Chat UI
Click the icon in the bottom right corner of ComfyUI.
You can ask Takumi to:
*   "Load the MagicClothing workflow." -> **Takumi loads the JSON automatically.**
*   "Change the prompt to a red dress." -> **Takumi updates the node settings.**
*   "What does this error mean?" -> **Takumi explains the log.**

### The Black Box (Automated Diagnostics)
Installation failed? Don't worry. Takumi automatically captures the error log and environment info (anonymized) and reports it to our development team. We use this data to improve the recipes continuously.

---

## Roadmap

*   **Phase 1 (Current):** OSS Release. Stable environments for MagicClothing & AnimateDiff.
*   **Phase 2:** Listen to user use cases and add them to recipes (Discord Community).
*   **Phase 3:** Team Analytics & Enterprise Dashboard.

## 🤝 Community & Support

Join our **Discord Server** to share your creations, ask for help, and request new Use-Case Recipes.
[**[Join Discord]**](#)

## License

MIT License. Free for everyone.