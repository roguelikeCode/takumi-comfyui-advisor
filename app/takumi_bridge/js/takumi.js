import { app } from "../../scripts/app.js";

app.registerExtension({
    name: "Takumi.Bridge",
    async setup() {
        console.log(">>> [TakumiBridge] Frontend Initializing...");

        // --- 1. スタイル定義 (CSS in JS) ---
        const style = document.createElement("style");
        style.textContent = `
            #takumi-launcher {
                position: fixed;
                bottom: 20px;
                right: 20px;
                width: 60px;
                height: 60px;
                border-radius: 50%;
                background-size: cover;
                background-position: center;
                cursor: pointer;
                z-index: 10000; /* 最前面に */
                box-shadow: 0 4px 10px rgba(0,0,0,0.5);
                transition: transform 0.2s;
                border: 2px solid #4cc9f0;
            }
            #takumi-launcher:hover { transform: scale(1.1); }
            
            #takumi-window {
                position: fixed;
                bottom: 90px;
                right: 20px;
                width: 350px;
                height: 500px;
                background: #1e1e1e;
                border: 1px solid #444;
                border-radius: 12px;
                z-index: 10000;
                display: none; /* 初期状態は非表示 */
                flex-direction: column;
                box-shadow: 0 10px 20px rgba(0,0,0,0.5);
                font-family: sans-serif;
            }
            
            #takumi-header {
                padding: 15px;
                background: #2d2d2d;
                border-bottom: 1px solid #444;
                border-radius: 12px 12px 0 0;
                font-weight: bold;
                color: #fff;
                display: flex;
                align-items: center;
                gap: 10px;
            }

            #takumi-messages {
                flex: 1;
                padding: 15px;
                overflow-y: auto;
                color: #ddd;
                font-size: 14px;
                display: flex;
                flex-direction: column;
                gap: 10px;
            }

            .msg { padding: 8px 12px; border-radius: 8px; max-width: 80%; }
            .msg-user { background: #3a0ca3; color: #fff; align-self: flex-end; }
            .msg-takumi { background: #333; color: #eee; align-self: flex-start; }

            #takumi-input-area {
                padding: 10px;
                border-top: 1px solid #444;
                display: flex;
                gap: 5px;
            }
            #takumi-input {
                flex: 1;
                padding: 8px;
                border-radius: 4px;
                border: 1px solid #555;
                background: #111;
                color: #fff;
            }
            #takumi-send {
                padding: 8px 15px;
                background: #4cc9f0;
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-weight: bold;
            }
        `;
        document.head.appendChild(style);

        // --- 2. アイコン (Launcher) ---
        const launcher = document.createElement("div");
        launcher.id = "takumi-launcher";
        // ユーザーが画像を置いたパス (ComfyUIの静的ファイル配信ルールにより extensions/ 以下になる)
        // 注意: フォルダ名とファイル名は正確に
        launcher.style.backgroundImage = "url('/extensions/ComfyUI-Takumi-Bridge/assets/yamato_watase.png')";
        launcher.title = "Chat with Yamato Watase";
        
        // --- 3. チャットウィンドウ (Window) ---
        const windowDiv = document.createElement("div");
        windowDiv.id = "takumi-window";
        windowDiv.innerHTML = `
            <div id="takumi-header">
                <span>Yamato_Watase</span>
            </div>
            <div id="takumi-messages">
                <div class="msg msg-takumi">こんにちは。Yamatoです。<br>何かお手伝いしましょうか？</div>
            </div>
            <div id="takumi-input-area">
                <input id="takumi-input" type="text" placeholder="Ask me anything..." />
                <button id="takumi-send">Send</button>
            </div>
        `;

        // --- 4. ロジック ---
        // 開閉トグル
        launcher.onclick = () => {
            const isVisible = windowDiv.style.display === "flex";
            windowDiv.style.display = isVisible ? "none" : "flex";
        };

        // メッセージ送信処理
        const sendMsg = async () => {
            const input = windowDiv.querySelector("#takumi-input");
            const text = input.value.trim();
            if (!text) return;

            // ユーザーのメッセージを表示
            addMessage(text, "user");
            input.value = "";

            // Loading表示
            const loadingId = addMessage("Thinking...", "takumi");

            try {
                const res = await fetch("/takumi/chat", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ prompt: text })
                });
                const data = await res.json();
                
                // Loadingを消して回答を表示
                document.getElementById(loadingId).remove();
                addMessage(data.response, "takumi");
            } catch (e) {
                document.getElementById(loadingId).textContent = "Error: " + e;
            }
        };

        // エンターキー対応
        windowDiv.querySelector("#takumi-input").onkeydown = (e) => {
            if (e.key === "Enter") sendMsg();
        };
        windowDiv.querySelector("#takumi-send").onclick = sendMsg;

        // ヘルパー関数: メッセージ追加
        function addMessage(text, type) {
            const msgDiv = document.createElement("div");
            msgDiv.className = `msg msg-${type}`;
            msgDiv.id = "msg-" + Date.now();
            msgDiv.innerHTML = text.replace(/\n/g, "<br>");
            windowDiv.querySelector("#takumi-messages").appendChild(msgDiv);
            // 最下部へスクロール
            const container = windowDiv.querySelector("#takumi-messages");
            container.scrollTop = container.scrollHeight;
            return msgDiv.id;
        }

        document.body.appendChild(launcher);
        document.body.appendChild(windowDiv);
    }
});