# 🛡️ Recommended Security & Performance Guide

Takumi Advisor is designed to be secure by default, but for maximum safety and stability, we recommend the following configurations for your host environment.

---

## 1. Memory Optimization (Avoid Crashes)

### The Problem
Large AI models (like WanVideo or Flux) require massive system RAM (24GB+).
On Windows (WSL2), Docker is often limited to 50% of your total RAM or 8GB by default. This causes **OOM (Out Of Memory) crashes** (`Exit Code 137`).

### The Solution: `.wslconfig`
Create a configuration file to unlock your hardware's potential.

1.  Press `Win + R`, type `%UserProfile%`, and press Enter.
2.  Create a file named `.wslconfig` (if it doesn't exist).
3.  Add the following content (adjust `memory` to your PC's capacity):

```ini
[wsl2]
# Assign as much RAM as possible (e.g.: Total 32GB -> 24GB for WSL, )
memory=24GB
# Swap helps prevent crashes when RAM is full
swap=32GB
# Enable localhost forwarding for web UI access
localhostForwarding=true
```

4.  Restart WSL: Open PowerShell and run `wsl --shutdown`.

---

## 2. Local Security Scanning (Docker Scout)

While we scan our images in CI/CD, we recommend running a health check on your local environment.

**Docker Scout** is a tool built into Docker Desktop to find vulnerabilities.

### Common

```bash
Run `Ubuntu`
Run `Docker Desktop`
(⚠️ NOT in `PowerShell`)

# 1. Go to the repository root
cd takumi-comfyui-advisor
# 2. Build the image first (if it doesn't exist)
make build
```

### Quick Scan
Run this command in your terminal to see a security summary of the Takumi image:

```bash
# 3. Run scan
docker scout quickview takumi-comfyui:latest
```

### Deep Dive
To see specific CVEs (Common Vulnerabilities and Exposures):

```bash
# 3. Run scan
docker scout cves takumi-comfyui:latest
```

**Note on Vulnerabilities:**

You may see a `CRITICAL` vulnerability flagged in `pkg:golang/stdlib` (related to Ollama).We classify this as an **acceptable risk** because:

1. It originates from the upstream Ollama binary (we must wait for their update).
2. Ollama operates within a restricted local container and is not exposed as a public web server.

---

## 3. User Namespace Remap (Hardening)

**User Namespace (userns-remap)** maps the container's `root` user to a low-privileged user on the host OS. Even if an attacker breaks out of the container as root, they will have zero privileges on your host machine.

### ⚠️ Warning
Enabling this feature changes the storage location of Docker images. **All your existing images and containers will seem to disappear.** You will need to rebuild or repull them. This is a system-wide change.

### Setup Guide (Ubuntu / WSL2)

1.  **Check User**
    Verify if the `dockremap` user exists 
    
    (created by Docker automatically):
    ```bash
    id dockremap
    ```
    If not found: sudo useradd dockremap 
    
    (id: ‘dockremap’: no such user)
    ```bash
    # 1. Create system users and groups
    sudo adduser --system --group dockremap

    # 2. Set the sub-ID range (subuid / subgid)
    # This sets the dockremap user to be assigned 65536 IDs starting from ID 165536.
    echo "dockremap:165536:65536" | sudo tee -a /etc/subuid
    echo "dockremap:165536:65536" | sudo tee -a /etc/subgid
    ```

2.  **Edit Configuration**
    Create or edit `/etc/docker/daemon.json`:
    ```bash
    sudo mkdir -p /etc/docker
    sudo nano /etc/docker/daemon.json
    ```
    Add the following configuration:
    
    (If you already have files, add them inside {}, separated by commas.)
    ```json
    {
      "userns-remap": "default"
    }

    Ctrl + X -> Y -> Enter
    ```

3.  **Restart Docker**
    For WSL2 with Docker Desktop, Right-click the whale icon on Docker Desktop and click "Restart".
    ```bash
    # sudo systemctl restart docker
    ```

---

## 4. Rootless Docker (Recommended Advanced Hardening)

**Rootless mode** runs the Docker Daemon itself as a non-root user. This is the ultimate security measure but may require complex configuration for NVIDIA GPU passthrough.

### Installation
Please refer to the official documentation, as steps vary by OS.
*   https://docs.docker.com/engine/security/rootless/

### NVIDIA GPU with Rootless
To use GPUs in Rootless mode, you must configure the NVIDIA Container Toolkit specifically for it.
1.  Ensure `nvidia-container-runtime` is installed.
2.  Edit `~/.config/docker/daemon.json` (user config):
    ```json
    {
      "runtimes": {
        "nvidia": {
          "path": "nvidia-container-runtime",
          "runtimeArgs": []
        }
      },
      "default-runtime": "nvidia"
    }
    ```
3.  **Note:** Takumi primarily supports standard Docker with `--user` flags. Rootless mode support is "Best Effort".

---

## 5. Takumi's Built-in Defenses

We have already implemented the following:

*   **Non-Root Execution:** Containers run as your host user (`UID:GID`), not root.
*   **Read-Only Filesystem:** Source code directories (`/app`, `/scripts`) are mounted as Read-Only to prevent tampering.
*   **Privilege Drop:** We disable `sudo` and other privilege escalation capabilities (`no-new-privileges`) inside the container.
*   **Trivy CI/CD:** Automated vulnerability scanning with Trivy at build and push time.
*   **Node Scanner:** A built-in scanner checks Custom Nodes for dangerous code patterns (`socket`, `subprocess`) during installation.
```

---

## 6. Update README (`README.md`)

Add a link to the guide.

```markdown:enterprise/takumi-comfyui-advisor-enterprise/core/README.md
# Takumi ComfyUI Advisor (OSS Edition)

... (Header) ...

## 🛡️ Security & Performance

We prioritize your safety and system stability.
Please check our **[Recommended Guide](docs/security/RECOMMENDED_GUIDE.md)** for:

*   **Preventing Crashes:** How to allocate enough RAM for WanVideo/Flux.
*   **Security Check:** How to scan your environment with Docker Scout.
*   **Advanced Hardening(recommended):** Running with Rootless Docker.

... (Footer) ...
```