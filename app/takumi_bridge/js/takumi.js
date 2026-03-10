import { app } from "../../scripts/app.js";

// =============================================================================
// [1] Configuration & Constants (Encapsulation)
// =============================================================================
const CONFIG = {
    ID: {
        LAUNCHER: "takumi-launcher",
        WINDOW: "takumi-window",
        HEADER: "takumi-header",
        MESSAGES: "takumi-messages",
        INPUT_AREA: "takumi-input-area",
        INPUT: "takumi-input",
        SEND_BTN: "takumi-send"
    },
    ASSETS: {
        // [Note] Ensure this path strictly matches the folder structure in custom_nodes.
        AVATAR: "/extensions/ComfyUI-Takumi-Bridge/assets/yamato_watase.png"
    },
    API: {
        CHAT: "/takumi/chat"
    }
};

// =============================================================================
// [2] UI Component (The View)
// =============================================================================
class TakumiUI {
    constructor() {
        this.launcher = null;
        this.window = null;
        this.messagesArea = null;
        this.inputField = null;
        this.sendBtn = null;
    }

    // [Why] To inject necessary CSS styles dynamically into the document head.
    // [What] Defines strictly scoped CSS for the chat interface.
    injectStyles() {
        const style = document.createElement("style");
        style.textContent = `
            #${CONFIG.ID.LAUNCHER} {
                position: fixed; bottom: 20px; right: 20px;
                width: 60px; height: 60px;
                border-radius: 50%;
                background-size: cover; background-position: center;
                cursor: pointer; z-index: 10000;
                box-shadow: 0 4px 10px rgba(0,0,0,0.5);
                transition: transform 0.2s;
                border: 2px solid #4cc9f0;
                background-image: url('${CONFIG.ASSETS.AVATAR}');
            }
            #${CONFIG.ID.LAUNCHER}:hover { transform: scale(1.1); }
            
            #${CONFIG.ID.WINDOW} {
                position: fixed; bottom: 90px; right: 20px;
                width: 350px; height: 500px;
                background: #1e1e1e; border: 1px solid #444; border-radius: 12px;
                z-index: 10000; display: none; flex-direction: column;
                box-shadow: 0 10px 20px rgba(0,0,0,0.5); font-family: sans-serif;
                user-select: text !important; -webkit-user-select: text !important; cursor: auto !important;
            }
            
            #${CONFIG.ID.HEADER} {
                padding: 15px; background: #2d2d2d; border-bottom: 1px solid #444;
                border-radius: 12px 12px 0 0; font-weight: bold; color: #fff;
                display: flex; align-items: center; gap: 10px;
            }

            #${CONFIG.ID.MESSAGES} {
                flex: 1; padding: 15px; overflow-y: auto; color: #ddd; font-size: 14px;
                display: flex; flex-direction: column; gap: 10px;
                user-select: text !important; cursor: text !important;
            }

            .takumi-msg { padding: 8px 12px; border-radius: 8px; max-width: 80%; line-height: 1.4; }
            .takumi-msg-user { background: #3a0ca3; color: #fff; align-self: flex-end; }
            .takumi-msg-takumi { background: #333; color: #eee; align-self: flex-start; }

            #${CONFIG.ID.INPUT_AREA} {
                padding: 10px; border-top: 1px solid #444; display: flex; gap: 5px;
            }
            
            #${CONFIG.ID.INPUT} {
                flex: 1; padding: 8px; border-radius: 4px; border: 1px solid #555;
                background: #111; color: #fff;
                user-select: text !important; cursor: text !important;
            }
            
            #${CONFIG.ID.SEND_BTN} {
                padding: 8px 15px; background: #4cc9f0; border: none;
                border-radius: 4px; cursor: pointer; font-weight: bold;
            }
        `;
        document.head.appendChild(style);
    }

    // [Why] To construct the DOM elements for the chat interface.
    // [What] Creates the Launcher, Window, and Input areas, appending them to the document body.
    buildDOM() {
        this.launcher = document.createElement("div");
        this.launcher.id = CONFIG.ID.LAUNCHER;
        this.launcher.title = "Access The Nexus";

        this.window = document.createElement("div");
        this.window.id = CONFIG.ID.WINDOW;
        this.window.innerHTML = `
            <div id="${CONFIG.ID.HEADER}">
                <span>Yamato Watase</span>
            </div>
            <div id="${CONFIG.ID.MESSAGES}">
                <div class="takumi-msg takumi-msg-takumi">Greetings. I am Yamato.<br>How may I optimize your workflow today?</div>
            </div>
            <div id="${CONFIG.ID.INPUT_AREA}">
                <input id="${CONFIG.ID.INPUT}" type="text" placeholder="Initiate sequence..." />
                <button id="${CONFIG.ID.SEND_BTN}">Send</button>
            </div>
        `;

        this.messagesArea = this.window.querySelector(`#${CONFIG.ID.MESSAGES}`);
        this.inputField = this.window.querySelector(`#${CONFIG.ID.INPUT}`);
        this.sendBtn = this.window.querySelector(`#${CONFIG.ID.SEND_BTN}`);

        document.body.appendChild(this.launcher);
        document.body.appendChild(this.window);
    }

    // [Why] To seamlessly append new messages to the chat history.
    // [What] Creates a styled div based on the sender ('user' or 'takumi') and scrolls into view.
    addMessage(text, sender) {
        const msgDiv = document.createElement("div");
        msgDiv.className = `takumi-msg takumi-msg-${sender}`;
        msgDiv.id = "msg-" + Date.now();
        msgDiv.innerHTML = text.replace(/\n/g, "<br>");
        
        this.messagesArea.appendChild(msgDiv);
        this.messagesArea.scrollTop = this.messagesArea.scrollHeight;
        
        return msgDiv.id;
    }

    // [Why] To toggle the visibility of the Nexus command center.
    toggleWindow() {
        const isVisible = this.window.style.display === "flex";
        this.window.style.display = isVisible ? "none" : "flex";
    }
}

// =============================================================================
// [3] Logic & Event Controller (The Brain)
// =============================================================================
class TakumiBridge {
    constructor() {
        this.ui = new TakumiUI();
        this.vramTimer = null;
    }

    // [Why] To orchestrate the initialization sequence of the interface.
    init() {
        console.log(">>> [TakumiBridge] Initializing Nexus Interface...");
        this.ui.injectStyles();
        this.ui.buildDOM();
        this.bindEvents();
        this.loadCatalog();
    }

    // [Why] To handle user interactions while strictly isolating them from ComfyUI's global events.
    // [What] Binds click and keydown events, stopping event propagation where necessary.
    bindEvents() {
        this.ui.launcher.onclick = () => this.ui.toggleWindow();

        const handleSend = () => this.sendMessage();
        
        this.ui.sendBtn.onclick = (e) => { 
            e.stopPropagation(); 
            handleSend(); 
        };

        this.ui.inputField.addEventListener("keydown", (e) => {
            if (e.isComposing) return;

            if (e.key === "Enter") {
                e.preventDefault();
                handleSend();
            }
            e.stopPropagation();
        });

        // The Event Shield: Prevents accidental interactions with underlying ComfyUI nodes.
        const stopPropagation = (e) => e.stopPropagation();
        this.ui.window.addEventListener('mousedown', stopPropagation);
        this.ui.window.addEventListener('mouseup', stopPropagation);
        this.ui.window.addEventListener('click', stopPropagation);
        this.ui.window.addEventListener('wheel', stopPropagation);
    }

    // [Why] To dynamically fetch available workflows to construct the Zero-Compute Menu.
    async loadCatalog() {
        try {
            const res = await fetch("/takumi/catalog");
            const catalog = await res.json();
            if (Object.keys(catalog).length > 0) {
                this.renderCatalogMenu(catalog);
            }
        } catch (e) {
            console.error(">>> [TakumiBridge] Failed to load workflow catalog:", e);
        }
    }

    // [Why] To provide instant access to workflows without invoking LLM inference.
    renderCatalogMenu(catalog) {
        const menuDiv = document.createElement("div");
        menuDiv.className = "takumi-msg takumi-msg-takumi";
        menuDiv.style.marginTop = "10px";
        menuDiv.innerHTML = `<span style="font-size:12px; color:#aaa;">🔻 Available Workflows:</span><br><br>`;
        
        Object.entries(catalog).forEach(([id, meta]) => {
            const btn = document.createElement("button");
            btn.textContent = `▶ ${meta.name}`;
            btn.style.cssText = `
                display: block; width: 100%; margin-bottom: 8px; padding: 10px;
                background: #2b2b2b; color: #4cc9f0; border: 1px solid #4cc9f0;
                border-radius: 6px; cursor: pointer; font-weight: bold;
                text-align: left; transition: background 0.2s;
            `;
            
            btn.onmouseover = () => {
                btn.style.background = "#4cc9f0";
                btn.style.color = "#000";
            };
            btn.onmouseout = () => {
                btn.style.background = "#2b2b2b";
                btn.style.color = "#4cc9f0";
            };
            
            btn.onclick = (e) => {
                e.stopPropagation();
                this.ui.inputField.value = meta.name;
                this.sendMessage();
            };
            menuDiv.appendChild(btn);
        });
        
        this.ui.messagesArea.appendChild(menuDiv);
        this.ui.messagesArea.scrollTop = this.ui.messagesArea.scrollHeight;
    }

    // [Why] To communicate with the backend API and orchestrate response actions.
    async sendMessage() {
        const text = this.ui.inputField.value.trim();
        if (!text) return;

        // Reset the VRAM unload timer to prevent premature teardown
        this.clearVramTimer();

        this.ui.addMessage(text, "user");
        this.ui.inputField.value = "";
        
        const loadingId = this.ui.addMessage("Thinking...", "takumi");

        try {
            const res = await fetch(CONFIG.API.CHAT, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ prompt: text })
            });
            const data = await res.json();
            
            const loadingMsg = document.getElementById(loadingId);
            if (loadingMsg) loadingMsg.remove();

            // 1. Initializing / Downloading State
            if (data.type === "downloading") {
                this.ui.addMessage(data.response, "takumi");
                return;
            }

            // 2. Fast Path (Workflow Deployment)
            if (data.type === "action") {
                this.ui.addMessage(data.message, "takumi");
                if (data.workflow) {
                     app.loadGraphData(data.workflow);
                     this.ui.addMessage("✅ Canvas updated successfully.", "takumi");
                }
                return; // Bypass the VRAM timer since LLM was not utilized
            } 
            
            // 3. Standard AI Inference (Text Response)
            this.ui.addMessage(data.response, "takumi");
            
            // Initiate the VRAM unload sequence post-inference
            this.startVramTimer();

        } catch (e) {
            const loadingMsg = document.getElementById(loadingId);
            if (loadingMsg) loadingMsg.textContent = "Error: " + e;
        }
    }

    // [Why] To manage the lifecycle of the VRAM unload countdown.
    clearVramTimer() {
        if (this.vramTimer) {
            clearTimeout(this.vramTimer);
            this.vramTimer = null;
        }
    }

    // [Why] To enforce hardware resource limits by notifying the user of VRAM release.
    startVramTimer() {
        this.clearVramTimer();
        this.vramTimer = setTimeout(() => {
            const msg = `
                🔌 <b>[System]</b><br>
                The AI model has been automatically unloaded from VRAM due to 20 seconds of inactivity.<br>
                <span style='font-size:12px; color:#888;'>* Compute resources for image/video generation are now maximized.</span>
            `;
            this.ui.addMessage(msg, "takumi");
            this.vramTimer = null;
        }, 20000);
    }
}

// =============================================================================
// [4] Registration
// =============================================================================
app.registerExtension({
    name: "Takumi.Bridge",
    setup() {
        const bridge = new TakumiBridge();
        bridge.init();
    }
});