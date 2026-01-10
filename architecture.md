# System Architecture & Design Principles

> **[Why]** To visualize the structural integrity and data flow of the Takumi system.
> **[What]** Documentation of the containerization strategy, installer logic, AI interaction, and telemetry pipelines.

---

## 1. High-Level Concept: "The Factory"

The system operates on a **"Container-First"** philosophy. The Host OS serves only as a launcher, while all logic, dependencies, and AI models reside inside a reproducible Docker container.

```mermaid
graph TD
    %% --- Global Settings ---
    linkStyle default stroke:#718096,stroke-width:2px,fill:none;

    %% --- Styles ---
    classDef host fill:#2d3748,stroke:#cbd5e0,stroke-width:2px,color:#ffffff;
    classDef container fill:#0d1b2a,stroke:#4cc9f0,stroke-width:3px,color:#ffffff;
    classDef cloud fill:#e2e8f0,stroke:#2d3748,stroke-width:2px,color:#0d1b2a;
    classDef plain fill:#f1f5f9,stroke:#94a3b8,stroke-width:2px,color:#0d1b2a;
    
    %% Fixed: Text color to Black (#000000) for visibility on light background
    classDef titleStyle fill:none,stroke:none,font-weight:bold,color:#000000;

    subgraph Host [" "]
        direction TB
        
        %% Title Node (Black Text)
        HostTitle["🖥️ Host OS<br/>(Windows/WSL2/Linux)"]:::titleStyle
        
        %% User Node
        User((User))
        
        %% Components
        Make[Makefile]
        Dotenv[.env Secrets]
        
        %% Layout
        HostTitle ~~~ User
    end

    subgraph Docker ["📦 Docker Container (Takumi OS)"]
        direction TB
        Installer["install.sh / Installer Engine"]
        Runtime[ComfyUI Runtime]
        Brain[Ollama / Gemma 2]
        Bridge[Takumi Bridge Server]
    end

    subgraph Cloud ["☁️ External World"]
        direction TB
        HuggingFace[Hugging Face Hub]
        AWS[AWS Telemetry Lake]
    end

    %% Connections (User initiates the flow)
    User -->|make install / run| Make
    Make -->|Injects| Dotenv
    Make -->|Builds & Runs| Docker
    
    Installer -->|Downloads| HuggingFace
    Runtime -->|Loads| HuggingFace
    Bridge -->|Queries| Brain
    Installer -.->|Reports Failure| AWS
    
    %% Apply Styles
    class User,Make,Dotenv host;
    class Installer,Runtime,Brain,Bridge container;
    class HuggingFace,AWS cloud;
    class Host,Cloud plain;
    class Docker container;
```

---

## 2. Installer Architecture: "The Modular Core"

The installation logic has been refactored from a monolithic script into a **Modular Architecture**.
The entry point (`install.sh`) acts as an orchestrator, loading specialized libraries to handle specific tasks.

```mermaid
graph LR
    %% --- Node Styles ---
    classDef entry fill:#4cc9f0,stroke:#ffffff,stroke-width:2px,color:#0d1b2a;
    classDef lib fill:#1a365d,stroke:#4cc9f0,stroke-width:1px,color:#ffffff;
    classDef data fill:#ffffff,stroke:#0d1b2a,stroke-width:2px,color:#0d1b2a;
    
    %% --- Subgraph Styles (Fix for Yellow Background) ---
    %% Fill: Very Light Blue-Gray (#f1f5f9) instead of Yellow
    classDef groupStyle fill:#f1f5f9,stroke:#475569,stroke-width:2px,color:#0d1b2a;

    Entry("app/install.sh"):::entry

    subgraph Libraries ["📚 app/lib/"]
        Utils(utils.sh):::lib
        Logger(logger.sh):::lib
        BrainInterface(brain.sh):::lib
        Diagnostics(diagnostics.sh):::lib
        Concierge(concierge.sh):::lib
        Core(installer.sh):::lib
    end

    subgraph Data ["💾 app/config/"]
        Recipes[("JSON Recipes")]:::data
        Catalog[("Node Catalog")]:::data
    end

    Entry -->|Source| Libraries
    Core -->|Read| Recipes
    Core -->|Merge| Catalog
    Concierge -->|Select| Recipes
    BrainInterface -->|Consult| Brain["scripts/brain.py"]
    
    %% Apply Subgraph Styles explicitly
    class Libraries,Data groupStyle;
```

### **Module Responsibilities**

| Module | Responsibility (What) |
| :--- | :--- |
| **`utils.sh`** | Global constants, paths, and state variables. |
| **`logger.sh`** | Standardized logging outputs and error traps. |
| **`diagnostics.sh`** | Hardware inspection (NVIDIA GPU/CUDA version). |
| **`concierge.sh`** | Interactive menu for Use-Case selection. |
| **`brain.sh`** | Interface to Python AI script for error analysis. |
| **`installer.sh`** | Core logic for Conda/Pip/Custom Nodes installation. |

---

## 3. The Brain & Bridge: "Natural Language Interface"

How the User talks to the System. The `Takumi Bridge` acts as a translator between the User's intent (Natural Language) and ComfyUI's internal logic (JSON Graphs).

```mermaid
sequenceDiagram
    %% --- Configuration ---
    participant User
    participant UI as Takumi UI (JS)
    participant Server as Bridge Server (Python)
    participant AI as Ollama (Gemma)
    participant Comfy as ComfyUI Core

    User->>UI: "I want to make an anime video"
    UI->>Server: POST /takumi/chat {prompt}
    
    %% Takumi's Brain Process
    %% Color: Matches Section 2's background (#f1f5f9 -> rgb(241, 245, 249))
    %% Note: Sequence diagrams do not support borders (stroke) on rects.
    rect rgb(241, 245, 249)
        Note over Server, AI: 🧠 Thought Process (Context Analysis)
        
        Server->>Server: Build System Prompt (Persona + Catalog)
        Server->>AI: Query (LLM Inference)
        AI-->>Server: JSON { action: "load_workflow", ... }
    end
    
    Server->>Server: WorkflowEngine.process_action()
    Server->>Server: Inject dynamic params (Prompt)
    
    Server-->>UI: Response { type: "action", workflow: JSON }
    UI->>Comfy: app.loadGraphData(workflow)
    Comfy-->>User: [Workflow Loaded on Canvas]
```

---

## 4. Telemetry Pipeline: "Dependency Resolver"

We collect data **only when things go wrong**.

```mermaid
graph LR
    %% --- Styles ---
    classDef client fill:#1a365d,stroke:#4cc9f0,stroke-width:2px,color:#ffffff;
    classDef cloud fill:#e2e8f0,stroke:#f4511e,stroke-width:2px,color:#0d1b2a;
    classDef plain fill:#f8fafc,stroke:#cbd5e0,stroke-width:2px,color:#0d1b2a;

    subgraph Client ["User Environment"]
        Trap["install.sh (Trap)"]:::client
        Reporter["scripts/resolve_dependencies"]:::client
    end

    subgraph Cloud ["AWS Serverless"]
        APIGW["API Gateway"]:::cloud
        Lambda["Lambda Function"]:::cloud
        S3[("S3 Data Lake")]:::cloud
    end

    Trap -- "On Error (Exit != 0)" --> Reporter
    Reporter -- "Gather Logs & Context" --> Reporter
    Reporter -- "POST JSON" --> APIGW
    APIGW --> Lambda
    Lambda -- "Store" --> S3
    
    class Client,Cloud plain;
```

---

## 5. Design Philosophy

### **Abstraction & Encapsulation**
We hide complexity. The user runs `make install`, and the system handles the chaos of Python versions, CUDA drivers, and compilation tools behind the scenes.

### **Idempotency**
You can run `make install` as many times as you want. The scripts check existing states and only apply necessary changes (Self-Healing).

### **Single Source of Truth**
*   **Version Control:** Git is the master.
*   **Environment:** Dockerfile is the definition.
*   **Recipes:** JSON files define the "correct" combination of libraries.
