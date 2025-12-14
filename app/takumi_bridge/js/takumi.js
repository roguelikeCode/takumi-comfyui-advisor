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
        // [Note] Ensure this path matches your folder structure in custom_nodes
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
    // [What] Defines scoped CSS for the chat interface.
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

            .takumi-msg { padding: 8px 12px; border-radius: 8px; max-width: 80%; }
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
    // [What] Creates Launcher, Window, Input areas and appends them to body.
    buildDOM() {
        // Launcher
        this.launcher = document.createElement("div");
        this.launcher.id = CONFIG.ID.LAUNCHER;
        this.launcher.title = "Chat with Yamato Watase";

        // Window
        this.window = document.createElement("div");
        this.window.id = CONFIG.ID.WINDOW;
        this.window.innerHTML = `
            <div id="${CONFIG.ID.HEADER}">
                <span>Yamato_Watase</span>
            </div>
            <div id="${CONFIG.ID.MESSAGES}">
                <div class="takumi-msg takumi-msg-takumi">こんにちは。Yamatoです。<br>何かお手伝いしましょうか？</div>
            </div>
            <div id="${CONFIG.ID.INPUT_AREA}">
                <input id="${CONFIG.ID.INPUT}" type="text" placeholder="Ask me anything..." />
                <button id="${CONFIG.ID.SEND_BTN}">Send</button>
            </div>
        `;

        // References
        this.messagesArea = this.window.querySelector(`#${CONFIG.ID.MESSAGES}`);
        this.inputField = this.window.querySelector(`#${CONFIG.ID.INPUT}`);
        this.sendBtn = this.window.querySelector(`#${CONFIG.ID.SEND_BTN}`);

        document.body.appendChild(this.launcher);
        document.body.appendChild(this.window);
    }

    // [Why] To display a new message in the chat history.
    // [What] Creates a div, sets class based on sender, and scrolls to bottom.
    addMessage(text, sender) {
        const msgDiv = document.createElement("div");
        msgDiv.className = `takumi-msg takumi-msg-${sender}`; // sender: 'user' or 'takumi'
        msgDiv.id = "msg-" + Date.now();
        msgDiv.innerHTML = text.replace(/\n/g, "<br>");
        this.messagesArea.appendChild(msgDiv);
        this.messagesArea.scrollTop = this.messagesArea.scrollHeight;
        return msgDiv.id;
    }

    // [Why] To show/hide the chat window.
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
    }

    // [Why] To initialize the bridge, setup UI, and bind events.
    init() {
        console.log(">>> [TakumiBridge] Initializing...");
        this.ui.injectStyles();
        this.ui.buildDOM();
        this.bindEvents();
    }

    // [Why] To handle user interactions while isolating them from ComfyUI's global shortcuts.
    // [What] Binds click and keydown events, stopping propagation where necessary.
    bindEvents() {
        // --- 1. Basic Controls ---
        // Toggle Window Visibility
        this.ui.launcher.onclick = () => this.ui.toggleWindow();

        // Send Message Trigger
        const handleSend = () => this.sendMessage();
        this.ui.sendBtn.onclick = (e) => { 
            // Prevent ComfyUI from detecting a click on the canvas
            e.stopPropagation(); 
            handleSend(); 
        };

        // --- 2. Input Field Handling (The Critical Part) ---
        this.ui.inputField.addEventListener("keydown", (e) => {
            // [Fix] Allow IME (Japanese Input) composition without triggering send
            if (e.isComposing) return;

            // Handle Enter Key for submission
            if (e.key === "Enter") {
                e.preventDefault(); // Prevent newline insertion
                handleSend();
            }

            // [Important] Stop Propagation Barrier
            // This prevents ComfyUI from intercepting keys (like 'Delete' or 'Backspace'),
            // while still allowing browser native behaviors (like Copy/Paste) to work within this input.
            e.stopPropagation();
        });

        // --- 3. Global Event Shield ---
        // [Why] To prevent accidental interactions with nodes behind the chat window.
        // [What] Stops all mouse/keyboard events originating inside the chat window.
        
        const stopPropagation = (e) => e.stopPropagation();

        // Protect against clicks and scrolling
        this.ui.window.addEventListener('mousedown', stopPropagation);
        this.ui.window.addEventListener('mouseup', stopPropagation);
        this.ui.window.addEventListener('click', stopPropagation);
        this.ui.window.addEventListener('wheel', stopPropagation);
    }

    // [Why] To communicate with the backend Python server.
    // [What] Sends prompt to /takumi/chat and handles the response (text or workflow action).
    async sendMessage() {
        const text = this.ui.inputField.value.trim();
        if (!text) return;

        // UI Update
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
            
            // Remove loading indicator
            const loadingMsg = document.getElementById(loadingId);
            if (loadingMsg) loadingMsg.remove();

            // Handle Response
            if (data.type === "action") {
                this.ui.addMessage(data.message, "takumi");
                if (data.workflow) {
                     app.loadGraphData(data.workflow);
                     this.ui.addMessage("✅ キャンバスを更新しました。", "takumi");
                }
            } else {
                this.ui.addMessage(data.response, "takumi");
            }

        } catch (e) {
            const loadingMsg = document.getElementById(loadingId);
            if (loadingMsg) loadingMsg.textContent = "Error: " + e;
        }
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