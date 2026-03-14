# Takumi ComfyUI Advisor

> **Stop Debugging. Start Creating.**
> The AI-Powered Concierge that saves you from Dependency Hell.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Python 3.11 | 3.12](https://img.shields.io/badge/python-3.11%20%7C%203.12-blue)](https://www.python.org/)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Conda](https://img.shields.io/badge/conda-%2344A833.svg?style=flat&logo=anaconda&logoColor=white)](https://docs.conda.io/)
[![Security Scan](https://github.com/roguelikeCode/takumi-comfyui-advisor/actions/workflows/security.yml/badge.svg)](https://github.com/roguelikeCode/takumi-comfyui-advisor/actions/workflows/security.yml)

![Takumi Demo](docs/assets/demo.gif)

---

## The Problem: "Creation Stops at Installation"

ComfyUI has revolutionized AI art, but the path to using it is paved with frustration.
Especially for creators on Windows, the reality is harsh:

*   **No one to talk to:** "The programmer is a Mac user and doesn't understand my Windows errors."
*   **Dependency hell:** "Why does NumPy break with `IMPORT FAILED` when I include other custom nodes?"
*   **C++ Build Nightmares:** "`insightface` or `onnxruntime` failed because Visual Studio Build Tools are not installed. I don't understand the warning."
*   **Version Mismatch:** "It works on my friend's PC, but crashes on my RTX 3090."
*   **Silent Failures:** "Out of nowhere, PyTorch falls back to the CPU version, which makes rendering incredibly slow. Why? I thought I installed the GPU version?"

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
    Just type `make install-oss`. Takumi handles Conda, CUDA, PyTorch, and all Custom Nodes automatically.

3.  **🤖 AI Concierge (Yamato_Watase)**
    Built-in LLM (Gemma 3) monitors your workflow. If an error occurs, Takumi explains it in plain language and guides you to the solution.

4.  **🧩 Verified Use-Cases (Recipes)**
    We give you **"Environments that Work,"** such as:
    *   👗 **Wan2.2 I2V 14B:** Wan 2.2 I2V Quantum (GGUF) + LightX2V Distill LoRA + GGUF quantization.
    *   👗 **ACE-Step 1.5:** lyrics using ACE-Step 1.5 + LyricForge.

5.  **📦 Asset Manager**
    Modern AI models require complex combinations of `Checkpoints`, `VAEs`, `Clips`, `LoRA` and `Motion Modules`. Takumi's "Asset Manager" downloads and links them automatically, solving the fragmented model problem.

---

## ⚡ Quick Start

### 0. Prerequisites & Optimization
Before running the installation, ensure your environment is ready.
Performance and Security settings are critical for a smooth experience.

(*⚠️ Please run all commands inside the `Ubuntu` terminal, NOT in `PowerShell`.*)

*   **System Requirements:**
    *   **Windows Users:** WSL2 (Ubuntu) is strictly required. (Enter `wsl --install` in `PowerShell`.)
    *   **NVIDIA GPU:** Drivers installed.
*   **Essential Configuration:**
    *   **[Security Guide](docs/security/RECOMMENDED_GUIDE.md):** Best practices for keeping your environment safe.
    *   **[WSL Performance Tuning](docs/performance/WSL_TUNING.md):** **Highly Recommended.** Optimize memory/CPU for AI workloads.
    *   **[Docker Settings](docs/security/DOCKER_SETTINGS.md):** Required configurations for GPU access.

### 1. Installation

**Step 1: Clone the repository**

This creates a folder named `takumi-comfyui-advisor` in your current location

```bash
git clone https://github.com/roguelikeCode/takumi-comfyui-advisor.git
cd takumi-comfyui-advisor
```

**Step 2: Setup Environment & Secrets (Zero-Trust)**

Takumi achieves a Zero-Trust architecture through the following layered structure:
1. **Doppler**  : Manages secret keys in a secure cloud environment (eliminates `.env` files).
2. **Tailscale**: Isolates containers into a private network.
3. **Tinyproxy**: Controls outbound communication by routing traffic through a strict whitelist.

**Action Required:**

**1. Setup Hugging Face (AI Models Platform)**
1. Register for a free account at [Hugging Face](https://huggingface.co/settings/tokens)
2. Click `Create new token` -> Token type: `Read` -> Token name: `Takumi-ComfyUI-Advisor`
3. Copy the generated token (`hf_...`)

**2. Setup Tailscale (VPN)**
1. Register for a free account at [Tailscale](https://tailscale.com/)
2. Click `Settings` -> `Keys` (Personal Settings) -> `Generate auth key` (Auth keys)
3. Turn on the following options:
   * `Reusable`
   * `Ephemeral`
   * `Pre-approved`
4. Click `Generate key`
5. Copy the generated token (`tskey-...`)

(*⚠️ `Tailscale` authentication keys **expire after 90 days**. When the system alerts you, please generate a new key and update it in `Doppler`.*)

**3. Setup Doppler (Cloud API Manager)**
1. Register for a free account at [Doppler](https://www.doppler.com/).
2. Click `Projects` -> Click `+` (Create Project) -> Name it `takumi-comfyui-advisor`
3. Click the **`dev`** environment and add the following Secrets:
   * `HF_TOKEN` = (`hf_...`)
   * `TAKUMI_LICENSE_KEY` = unlicensed
   * `TAKUMI_PRIVACY_LEVEL` = 2
   * `TS_AUTHKEY` = (`tskey-...`)

**4. Bind Your Local Environment**
Open your terminal in the project root and link your local machine to Doppler:

```bash
# 1. Install Doppler CLI (Ubuntu/WSL2/Linux)
(curl -Ls https://cli.doppler.com/install.sh || wget -qO- https://cli.doppler.com/install.sh) | sudo sh

# 2. Login to Doppler (Browser will open)
doppler login

# 3. Bind this folder to the Doppler project
doppler setup
# (Select 'takumi-comfyui-advisor' -> 'dev')

# 4. Verify the Zero-Trust connection
make setup-oss
```

**Step 3: Build**

Select your desired use-case number from the menu (e.g., Wan2.2)

```bash
make install-oss
```

### 2. Run

```bash
make run-oss
```

**How to use:**
1.  Open your browser at `http://localhost:8188`
2.  Click the chat icon (bottom right)
3.  Click the button (Workflow)

*(To stop the application, press `make stop-oss` in the terminal)*

---

## Features

### Takumi Chat UI
Click the icon in the bottom right corner of ComfyUI.

*(Currently under development)*

### The Black Box (Automated Diagnostics)
Installation failed? Don't worry. Takumi automatically captures the error log and environment info (anonymized) and reports it to our development team. We use this data to improve the recipes continuously.

---

## Roadmap

*   **Phase 1 (Current):** OSS Release. Stable environments for MagicClothing & AnimateDiff.
*   **Phase 2:** Listen to user use cases and add them to recipes (Discord Community).
*   **Phase 3:** Team Analytics & Enterprise Dashboard.
*   **Future Vision:** Sustainable Creator Economy & Revenue Sharing (Web 3.0).

## 🤝 Community & Support

Join our **Discord Server** to share your creations, ask for help, and request new Use-Case Recipes.
[![Discord](https://img.shields.io/discord/1449713759898832984?color=7289da&label=Discord&logo=discord&logoColor=white)](https://discord.gg/n2KSKjTkAa)

## License

[GNU AGPL v3.0](LICENSE) © 2025 Yamato Watase