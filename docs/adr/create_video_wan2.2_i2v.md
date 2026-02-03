## 1. Context
* **The goal:** To establish a cinematic video generation workflow using Image-to-Video (I2V).We need a solution that bridges the gap between **"Cinematic Quality"** and **"Consumer Hardware (12GB VRAM)"**.

* **HunyuanVideo (Tencent):** Excellent quality, but requires **24GB+ VRAM** (RTX 3090/4090 required). This excludes 90% of Creators (Low VRAM).

## 2.Decision
We adopt **Wan 2.2 (14B)** combined with **GGUF Quantization** and **LightX2V LoRA**.

### A. Core Engine: Wan 2.2 I2V (High & Low Noise)
* **Reason:** Wan 2.2 I2V provides split checkpoints based on noise conditioning. We install both to cover all use cases
* **I2V Strategy:** We use Image-to-Video to leverage our "SDXL images" assets as perfect keyframes.
* **High Noise Model (`wan2.2_i2v_high_noise...`):** For dramatic motion and transformations.
* **Low Noise Model (`wan2.2_i2v_low_noise...`):** For subtle animation and high fidelity to the source image.

### B. Optimization: GGUF Q4_K_M
* **Technology:** 4-bit Quantization (GGUF format).
* **Impact:** Compresses the 14B model from ~28GB (FP16) to **~8.5GB**.
* **VRAM Management:** 
* UNet (GGUF): On GPU. 
* T5 Encoder (Text): **CPU Offload** (Aggressive swapping). 
* VAE: On GPU. 

### C. Acceleration: LightX2V LoRA
* **Adoption:** `Wan_2_2_I2V...lightx2v_MoE_distill_lora.safetensors`
* **Reason:** This is a **Unified MoE (Mixture of Experts)** version that works efficiently with both High and Low noise models, reducing sampling steps to ~10.

## 3. Technical Stack
* **Loader:** `ComfyUI-GGUF` (by City96) - Required to load `.gguf` weights.

## 4. Consequences
* **Positive:** **Flexibility:** Creators can switch between "Dynamic" and "Stable" motion without changing the workflow structure.
* **Negative:** Requires disk space for two 8.5GB models (Total ~17GB for UNet).