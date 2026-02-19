## 0. The Three Shields Architecture

To ensure ultimate safety in the age of generative AI, Takumi operates under a strict "Zero Trust" philosophy, protected by three physical and logical shields:

1. **The Identity Shield (Rootless Docker):** Protects the Host OS. By running without root privileges, even if an attacker breaks out of the container, they remain a powerless user on your machine.
2. **The File Shield (Immutable Root):** Protects the container's internal state. The root filesystem is strictly `read_only`, meaning malicious scripts literally have nowhere to install or hide.
3. **The Network Shield (Egress Filtering):** Protects against data exfiltration. A dedicated proxy gatekeeper blocks all outbound traffic, allowing connections only to explicitly whitelisted domains (e.g., Hugging Face, GitHub).

---

## 1. Automated Node Scanner (Bandit)

ComfyUI allows Custom Nodes to execute arbitrary Python code, which creates a risk of supply chain attacks.
Takumi automatically scans installed nodes using **Bandit** (a security linter).

### Understanding the Warning
If you see the following message during installation:

`WARN: ⚠️ Security risks detected by Bandit!`

It means the node contains code capable of **system operations** (e.g., file deletion, network access).

*   **False Positives:** Many legitimate nodes (e.g., Video helpers, Model downloaders) trigger this warning because they *need* these permissions to function.
*   **True Positives:** Malicious nodes use similar code to steal secrets or harm your system.

### Recommended Actions
If a warning appears for an unknown node:

1.  **Verify:** Search the node name on GitHub, Reddit, or X (Twitter). Is it widely used and trusted by the community?
2.  **Analyze:** Look at the file path shown in the log. Is the code doing what it claims to do?
3.  **Quarantine:** If you are unsure, **uninstall the node immediately**. Do not run it until you get confirmation from the developers.

---

## 2. Local Security Scanning (Docker Scout)

While we scan our images in CI/CD, we recommend running a health check on your local environment.

**Docker Scout** is a tool built into Docker Desktop to find vulnerabilities.

### Prerequisites


*   Ensure **Docker Desktop** is running.
*   Open your **Ubuntu** terminal. (⚠️ NOT in `PowerShell`)

```bash
# 1. Go to the repository root
cd takumi-comfyui-advisor
# 2. Build the image first (if it doesn't exist)
make build
```

### Quick Scan
Run this command to see a security summary of the Takumi image:

```bash
# 3. Run scan summary
docker scout quickview takumi-comfyui:latest
```

### Deep Dive
To see specific CVEs (Common Vulnerabilities and Exposures):

```bash
# 3. Run detailed scan
docker scout cves takumi-comfyui:latest
```

**Note on Vulnerabilities:**

You may see a `CRITICAL` vulnerability flagged in `pkg:golang/stdlib` (related to Ollama). We classify this as an **acceptable risk** because:

1. It originates from the upstream Ollama binary (we must wait for their update).
2. Ollama operates within a restricted local container and is not exposed as a public web server.

---

## 3. Layered Defense Architecture

We have implemented a multi-layered security strategy:

*   **Secret Encryption:** `dotenvx` encrypts sensitive environment variables (API Keys).
*   **CI/CD Scanning:** Automated vulnerability scanning with **Trivy** during build and push.
*   **Principle of Least Privilege (最小権限の原則):** The container starts, fixes permissions, and immediately drops to a non-root user via `gosu`. We apply `--cap-drop=ALL` to strip Linux kernel privileges, adding back only what is strictly necessary.
*   **Egress Filtering (Network Isolation):** We use a Sidecar Proxy (`tinyproxy`) to enforce strict domain whitelisting. Even if a malicious custom node tries to steal your API keys or Discord tokens, the proxy will block the outbound connection to unauthorized servers.
*   **Ephemeral Workspaces (`tmpfs`):** For directories that absolutely require write access during runtime (e.g., `/tmp`, `/run`), we use `tmpfs` mounts. This means data is stored only in RAM. If an attacker manages to hide a malicious payload in these temporary folders, it will be physically and permanently wiped out the moment the container is restarted.
