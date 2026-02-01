## 1. Memory Optimization (Avoid Crashes)

### The Problem
Large AI models (like WanVideo or Flux) require massive system RAM (24GB+).

On Windows (WSL2), Docker is often limited to 50% of your total RAM or 8GB by default. This causes **OOM (Out Of Memory) crashes** (`Exit Code 137`).

### Option A: Automatic Setup (Recommended)
We have prepared a PowerShell script to automatically configure your `.wslconfig` based on your hardware.

1.  Open the folder containing this repository in **Windows Explorer**.
    *   (e.g., `\\wsl.localhost\Ubuntu\home\yourname\takumi-comfyui-advisor\setup`)
2.  Right-click `setup_windows.ps1`.
3.  Select **"Run with PowerShell"**.
    *   This will create a `.wslconfig` file in your home directory and "restart WSL".
    *   If a permission error occurs, try Option B


### Option B: Manual Setup
If the script doesn't work, create the configuration file manually.

1.  **Open Location:** Press `Win + R`, type `%UserProfile%`, and press Enter.
2.  **Create File:** Create a file named `.wslconfig`.
    *   ⚠️ **Important:** Ensure the file does **NOT** end with `.txt`. (e.g., `.wslconfig.txt` will NOT work).
3.  **Edit:** Paste the following content. **Adjust `memory` to match your PC.**

```ini
[wsl2]
# Allocate 75% of RAM (e.g., 32GB total -> 24GB)
memory=24GB
# Swap prevents crashes when RAM is full. Keep this high.
swap=32GB
# Enable localhost forwarding for web UI access
localhostForwarding=true
```

4.  **Apply Changes:** Open `PowerShell` (⚠️ NOT in `Ubuntu`) and run:

```powershell
wsl --shutdown
```
