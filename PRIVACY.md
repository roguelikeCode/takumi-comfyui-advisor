# Privacy Policy

At **Takumi ComfyUI Advisor**, we believe that trust is the foundation of any creative tool. We are committed to transparency regarding what data we collect, why we collect it, and how you can control it.

### Regarding AI Processing
Takumi's chat features are powered by a local AI (Gemma 2) running entirely on your machine via Ollama.
**Your prompts are processed locally, never transmitted to the cloud, and never used to train our models.**

## 1. What We Collect (Telemetry)

To improve the stability of the installer and the quality of our advice, Takumi collects anonymous usage data **only in specific situations**.

### When Installation Fails (The Black Box)
If `make install` fails, the following information is automatically sent to our development team to help fix the bug:
*   **Error Logs:** The last 50-100 lines of the installation log.
*   **System Info:** OS type (e.g., Ubuntu 22.04), Python version, and basic GPU information.
*   **Recipe ID:** Which use-case you were trying to install (e.g., `animate_diff_video`).
*   **Anonymization:** Usernames in file paths (e.g., `/home/roguelikeCode/...`) are automatically replaced with `<USER>` before transmission.

---

## 2. What We DO NOT Collect

We strictly respect your creative privacy. We **NEVER** collect:

*   ❌ **Your Generated Images:** Your art stays on your machine.
*   ❌ **Your Prompts:** The text you type into ComfyUI or Takumi Chat is not sent to our servers for logging purposes.
*   ❌ **Personal Identifiable Information:** We do not collect names, email addresses, or precise locations.

---

## 3. How to Opt-Out

You have full control over data collection.
To disable all telemetry, set the following environment variable in your `.env` file:

```bash
TAKUMI_PRIVACY_LEVEL=0
```

*   **Level 0:** No data collection. (Silent Mode)
*   **Level 1:** Masked collection (Enterprise default). Prompts and sensitive info are redacted.
*   **Level 2:** Standard collection (OSS default). Helpful for improving the project.

---

## 4. Where Data Goes

Data is sent securely via HTTPS to our managed cloud infrastructure (AWS). It is stored in a private data lake and accessed only by the core development team for debugging and analysis purposes. We do not sell this data to third parties.

## 5. Contact

If you have questions about this policy, please open an issue on our [GitHub Repository](https://github.com/roguelikeCode/takumi-comfyui-advisor).
