## 1. Rootless Docker (The Ultimate Defense)

Takumi is designed to run on **Rootless Docker**.
This is our primary defense strategy against container breakouts.

**⚠️ Conflict Warning**
*   If you are currently using **Docker Desktop**, **DO NOT** run this script. It will cause system-wide conflicts.
*   However, for maximum security, **we strongly recommend migrating** to Rootless Docker eventually.

### Option A: Automatic Setup (Recommended)
We provide an automated script to migrate from Docker Desktop to Rootless Docker.

This script also handles the complex NVIDIA Container Toolkit configuration for rootless mode.

```bash
# 1. Enter the directory
cd takumi-comfyui-advisor

# 2. Run the setup script
bash setup/setup_rootless.sh

# 3. Reload environment (Important)
source ~/.bashrc
```

### Option B: Manual Setup
Configuring GPU support in Rootless mode requires precise edits to the Daemon and NVIDIA config.

If you cannot use the script, please refer to the official documentation:

*   [Run the Docker daemon as a non-root user (Rootless mode)](https://docs.docker.com/engine/security/rootless/)
*   [NVIDIA Container Toolkit: Rootless Support](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#rootless-mode)

**Critical Fix for WSL2 Users:**
Rootless Docker usually fails to access GPUs due to cgroup permission errors.
You must disable cgroups in the NVIDIA config:

```bash
# Edit /etc/nvidia-container-runtime/config.toml
# Change "no-cgroups = false" to "true"
no-cgroups = true
```

## 2. The Double Barrier
By stripping root privileges from the Docker Daemon, we construct a double layer of defense:

1.  **Identity Shield (Rootless):**
    *   Even if an attacker gains `root` access inside the container, they map to a **powerless user** (e.g., UID 1001) on your Host OS.
    *   They cannot modify system files (`/usr`, `/etc`) or install system-wide malware on your Windows/Linux machine.

2. **Write Protection (Immutable Infrastructure):**
    *   Core directories like `/app` and `/scripts` are **NOT mounted** from the host. The code is baked into the Docker image during the build process.
    *   Furthermore, the container runs with a **Read-Only root filesystem** (`read_only: true`). This ensures that even if an attacker breaches the container, they literally cannot download or save malware to the system.