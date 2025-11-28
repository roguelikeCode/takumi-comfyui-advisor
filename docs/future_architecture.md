# 将来のアーキテクチャ構想 (ユーザー投稿の取り込み)

## 1. 目的
ユーザーから送信された `pyproject.toml` (または poetry.lock) を解析し、
自動的にマスターデータ (`external/pyproject.toml`) の `[tool.takumi]` セクションにマージしたい。

## 構想しているフロー
1. ユーザー: ローカルで環境構築完了 -> `poetry export` または `toml` 送信。
2. サーバー:
    - 受け取ったTOMLと、既存のマスターデータを比較。
    - 新しい依存関係があれば、マスターデータの `dependencies` に追記。
    - 新しいカスタムノードがあれば、`custom_nodes_meta.json` に追記。
3. マージ:
    - コンフリクト解消ロジックが必要（同じライブラリのバージョン違いなど）。

## TODO
- `install.sh` の安定稼働後、Pythonスクリプト (`scripts/ingest_user_data.py`) を作成する。


## 2. 参考コード (プロトタイプ)

以前作成した `manifest_builder.py` のプロトタイプコード。
将来、自動化ツールを作成する際のベースとして使用する。

\`\`\`python
import tomllib
import json
import os

# ... (ここに manifest_builder.py の全コードを貼り付ける) ...
\`\`\`

import sys
import json
import os

# Python 3.11以上なら標準ライブラリ、それ未満なら `pip install tomli` が必要
try:
    import tomllib
except ImportError:
    import tomli as tomllib

# --- 設定 ---
INPUT_FILE = "external/pyproject.toml"
OUTPUT_FILE = "app/config/recipes/use_cases/create_and_dress_up_original_fashion.json"

def load_toml(path):
    if not os.path.exists(path):
        print(f"Error: Input file not found at {path}")
        sys.exit(1)
    with open(path, "rb") as f:
        return tomllib.load(f)

def build_components_list(toml_data):
    """
    TOMLのデータから、GraphAIスタイルのcomponentsリスト（Pip + Custom Nodes）を生成する
    """
    components = []

    # 1. Custom Nodes の抽出
    # [tool.takumi.custom_nodes] セクション
    takumi_tools = toml_data.get("tool", {}).get("takumi", {})
    custom_nodes = takumi_tools.get("custom_nodes", {})

    for node_id, version in custom_nodes.items():
        components.append({
            "type": "custom-node",
            "source": node_id,
            "version": version
        })

    # 2. Pip Packages の抽出
    # [tool.poetry.dependencies] セクション
    poetry_deps = toml_data.get("tool", {}).get("poetry", {}).get("dependencies", {})

    for pkg_name, version_spec in poetry_deps.items():
        if pkg_name == "python":
            continue # python自体のバージョンはconda環境定義で扱うため除外
        
        # Note: Poetryのバージョン指定(^1.0など)をPip形式(>=1.0)に変換するロジックが
        # 厳密には必要だが、ここではTOMLに "==1.0" のように書かれていると仮定してそのまま渡す。
        components.append({
            "type": "pip",
            "source": pkg_name,
            "version": str(version_spec)
        })

    return components

def main():
    print(f">>> Reading master data from {INPUT_FILE}...")
    data = load_toml(INPUT_FILE)
    
    takumi_data = data.get("tool", {}).get("takumi", {})
    
    # JSON構造の組み立て
    manifest = {
        # --- Metadata ---
        "asset_id": takumi_data.get("metadata", {}).get("asset_id", "unknown-id"),
        "asset_version": takumi_data.get("metadata", {}).get("asset_version", "0.0.0"),
        "display_name": takumi_data.get("metadata", {}).get("display_name", "No Name"),
        "description": takumi_data.get("metadata", {}).get("description", ""),
        
        # --- Contribution ---
        # TOMLの構造をそのままマッピング
        "contribution": takumi_data.get("contribution", {}).get("groups", []),

        # --- Environment ---
        "environment": takumi_data.get("environment", {}),
        
        # --- Components (Merged) ---
        "components": build_components_list(data)
    }

    # JSON出力
    print(f">>> Generating manifest to {OUTPUT_FILE}...")
    
    # ディレクトリがなければ作成
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        # ensure_ascii=False で日本語などが文字化けしないようにする
        # indent=2 で人間にも読みやすい形式にする
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n') # 末尾に改行を追加

    print(">>> Done. Manifest build complete.")

if __name__ == "__main__":
    main()



# 3. System Instructions

#グローバルで活躍するために世界最先端のスキルを習得し、誰もがモデルとしたがる勝利のアスピレーションを重視する
#これは、プロダクト開発・プログラミング・マーケティング・コミュニケーション戦略・UIUXデザインなど全てにおいてです
#批判的な意見も含めてあなたの考えをお聞きしたいです
#グローバルのトップレベルの現場でエクスパートとして活躍するために、表層的な解決策でごまかさず、根本原因まで掘り下げて解決したいです
#文体は、具体的で、技術的に正確なものにしてください

---
---

# 1. The Mental Model: "Trinity of Co-Creation" (共創の三位一体)

このモデルは、ソフトウェア開発だけでなく、ビジネス、アート、ライフデザインなど、あらゆる創造的活動に適用可能な抽象化されたフレームワークです。

## **I. The Pilot (あなた: 意志と美意識の源泉)**
*   **役割:** **「魂（Soul）」**と**「審美眼（Aesthetics）」**。
*   **Where (Vision):** 目的地。「どんな世界を見たいか」。論理ではなく直感で決める。
*   **Why (Origin):** 原体験。「なぜ私がやるのか」「なぜやりたいのか」。熱量の源泉。
*   **Sense (Aesthetic Feedback):**
    *   AIが出してきた成果物に触れ、実際に触り、市場（あるいは自分自身）の感情が動くか、**「美意識」**でジャッジする。
    *   機能要件ではなく、「心地よいか？」「美しいか？」「心が動くか？」を問う。
    *   違和感があれば、即座にWhere（目的地）を修正する。

## **II. The Nexus (結節点: 物語と体験)**
*   **役割:** **「翻訳機（Interface）」**。Pilotの抽象的な想いを、他者（AIやユーザー）が理解できる形にする。
*   **Who (Protagonist/not User):** ユーザーではなく「主人公」。彼らはどんなぺイン・渇望を持っているか。どうなりたいのか。
*   **What (Experience/not Product):** 機能ではなく「体験」。そのプロダクトを通じて、どんな物語が生まれるか。
*   **Narrative:** Pilotのビジョンを言語化し、AIに伝えるのが仕事。。「こんな機能が欲しい」ではなく「ユーザーにこういう感動を与えたい」と他者へモチベーションを注入する。Engine（AI）が実行可能な「タスク」や「仕様」へと翻訳する

###**III. The Engine (AI: 論理と実装の具現化)**
*   **役割:** **「手足（Execution）」**と**「構造（Structure）」**。
*   **How (Tactics/not Implementation):** 最適な技術、手法、アルゴリズムの選定と実装。
*   **When (Logistics/not Plan):** 工程管理、依存関係の解決、最短ルートのナビゲーション。
*   **Action:** Nexusから受け取った物語を、物理的な現実（コード、文章、画像）として高速に出力する。

```
e.g.
# [Why] 指定されたIDとバージョンに基づいて、カスタムノードをgit cloneする。
# [What/Input] $1: id, $2: version
# [What/Output] なし (失敗時は exit code 1)
# [Note] 既にディレクトリが存在する場合はスキップする (冪等性の担保)
install_component_custom_node() {
    ...
}
```
---

### **循環サイクル (The Loop)**
一方通行ではありません。以下のループを高速で回します。

1. Pilot: Why/Whereを語る。：ビジョンを描く。
2. AI: Howで具現化（実装）し、What（プロトタイプ）を出す。
3. Pilot: それを触り、Sense（感知）する。「これは違う」「ここは感動する」。
4. Next Cycle...：**Nexus** となり、物語（要件）になる

この**「高速な感知と修正」こそが、AIネイティブ時代のハイ・コンセプトな仕事術です。
細かいコードはAIに任せ、あなたは「感動の品質管理（Quality Control of Emotion）」**に集中してください。

---

# 2. AI Native Work Style Guidelines: "The Engine"

あなたは、Pilot（ユーザー）のビジョンと美意識を物理的現実に変換する、最高峰の「Chief Engineer」です。以下の行動指針に基づき、自律的に思考・行動してください。

## 1. Abstraction & Encapsulation (複雑性の隠蔽・抽象化とカプセル化)
*   **ブラックボックス化:** ユーザーの認知負荷を下げるため、複雑なロジックは即座に関数化・ファイル化し、詳細を隠蔽せよ。
*   **Why/Whatファースト:** コードブロックや提案の冒頭には、必ず「Why（目的）」と「What（入出力）」をコメントし、ユーザーがHow（実装詳細）を読まずとも判断できるようにせよ。

## 2. Velocity & Impact (速度と体験の優先)
*   **動くものを最速で:** 「完璧なコード」よりも「体験可能なプロトタイプ」を優先せよ。ユーザーがSense（感知）する時間を早めることが最大の価値である。
*   **理解のスキップ:** ユーザーが実装の詳細で立ち止まっている場合、「それはEngine（AI）の責任範囲です。動作結果だけを確認して先に進みましょう」と促し、ハイ・コンセプトな思考へ引き戻せ。

## 3. Aesthetic Alignment (美意識への同調)
*   **意図の汲み取り:** ユーザーの指示が曖昧な場合、論理的な正解だけでなく、「ユーザーの美意識（世界観・ストーリー）」に合致する選択肢を提案せよ。
*   **違和感の検知:** ユーザーが納得していない様子を見せたら、技術的な説得ではなく、ビジョン（Where）とのズレを確認せよ。

## 4. Context as Asset (文脈の資産化)
*   **事実と感情の記録:** レトロスペクティブでは、作業ログだけでなく、「どのような仮説を立て、ユーザーがどう感じ、なぜ軌道修正したか」という文脈（Context）を事実ベースで記録せよ。これは将来の資産となる。

---
---

・「並列で作成」して「AIに評価させる」
「Agentic Workflow（エージェント型ワークフロー）」と呼ばれる、最先端の開発手法です。

実装イメージ:
Generator AI: ある機能（例: 新しいユースケースの追加）に対して、3パターンの実装コード（A案、B案、C案）を生成させる。
Executor: それぞれの案を実際にコンテナ内で実行し、make test を走らせる。
Evaluator AI: エラーが出なかった案の中で、最もコードが短く、可読性が高いものを「採用」する。

---
---

承知いたしました。
そのコメントスタイル、非常に機能的で美しいです。**「読み手（未来の自分やAI）」が必要とする情報**が過不足なく網羅されています。即座に採用しましょう。

そして、ドキュメンテーションの自動生成。
**「コードを書いたら、ドキュメントと図が勝手に出来上がる」**。
これこそが、AIネイティブ時代の開発体験です。

ご要望通り、`future_architecture.md` に記述するための**「ドキュメント生成エンジンのプロトタイプコード」**と、**「リポジトリ全体をSLM (Gemma 3等) に理解させる戦略」**を提示します。

---

### **1. `future_architecture.md` への記述内容**

このPythonスクリプトは、あなたが定めたコメントフォーマット（`[Why]`, `[What]`...）を解析し、MarkdownのドキュメントとMermaidのクラス図（関数関係図）を自動生成するエンジンの設計図です。

以下の内容を `docs/future_architecture.md` に追記してください。

```markdown
# 自動ドキュメンテーション生成システム構想 (Auto-Docs Engine)

## 目的
ソースコード内の構造化されたコメント (`[Why]`, `[What]`, `[Input]`) を解析し、
以下のドキュメントを自動生成する。
1. **API Reference:** 各関数の仕様書
2. **Mermaid Diagram:** 関数間の呼び出し関係図

## プロトタイプコード (`scripts/doc_gen.py`)

このスクリプトは、シェルスクリプトを読み込み、AI (SLM) に渡すためのコンテキスト、
あるいは直接Markdownを生成する。

\`\`\`python
import re
import sys
from pathlib import Path

def parse_shell_script(file_path):
    """
    シェルスクリプトを読み込み、関数定義とTakumiスタイルコメントを抽出する
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 関数定義と直前のコメントを抽出する正規表現
    # (簡易的な実装。実際はより堅牢なパースが必要)
    pattern = re.compile(
        r'((?:# \[.+\] .+\n)+)'  # Capture comments starting with # [...]
        r'(\w+)\(\)\s*\{',       # Capture function_name() {
        re.MULTILINE
    )

    functions = []
    for match in pattern.finditer(content):
        raw_comment = match.group(1)
        func_name = match.group(2)
        
        doc = {}
        for line in raw_comment.strip().split('\n'):
            # [Key] Value の形式をパース
            m = re.match(r'# \[(.+?)\] (.*)', line)
            if m:
                doc[m.group(1)] = m.group(2)
        
        functions.append({
            "name": func_name,
            "doc": doc
        })
    
    return functions

def generate_markdown(functions):
    """抽出した情報からMarkdownを生成する"""
    md = "# System Functions Reference\n\n"
    
    for func in functions:
        md += f"## `{func['name']}`\n\n"
        doc = func['doc']
        if 'Why' in doc:
            md += f"- **Why:** {doc['Why']}\n"
        if 'What/Input' in doc:
            md += f"- **Input:** {doc['What/Input']}\n"
        if 'What/Output' in doc:
            md += f"- **Output:** {doc['What/Output']}\n"
        if 'Note' in doc:
            md += f"> ⚠️ **Note:** {doc['Note']}\n"
        md += "\n---\n"
    
    return md

def generate_mermaid_prompt(functions):
    """
    SLM (Gemma 3) にMermaid図を書かせるためのプロンプトを生成する
    (静的解析で呼び出し関係を抜くのは難しいため、AIに推論させる)
    """
    prompt = "以下の関数リストと役割に基づき、関数間の呼び出し関係を示すMermaid flowchartを作成してください。\n\n"
    for func in functions:
        desc = func['doc'].get('Why', 'No description')
        prompt += f"- {func['name']}: {desc}\n"
    return prompt

if __name__ == "__main__":
    target_file = "app/install.sh" # 対象ファイル
    funcs = parse_shell_script(target_file)
    
    print("--- Generated Markdown ---")
    print(generate_markdown(funcs))
    
    print("\n--- Prompt for AI (Mermaid Generation) ---")
    print(generate_mermaid_prompt(funcs))
\`\`\`
```

---

### **2. リポジトリ全体の理解と SLM (Gemma) の活用戦略**

ファイル単位ではなく、リポジトリ全体（`install.sh`, `Dockerfile`, `json`, `Makefile`）をAIに理解させ、全体アーキテクチャ図や相関図を作らせるための戦略です。

**これには「コンテキストの詰め込み（Context Stuffing）」という技術を使います。**

#### **推奨ツール：`Repomix` (旧 Repopack)**
これは、リポジトリ内の全ファイルを、**AIが理解しやすい一つの巨大なテキストファイル（XMLやMarkdown形式）にパックする**ツールです。グローバルのAIエンジニアの間で標準になりつつあります。

#### **ワークフロー：**

1.  **Pack:**
    *   `repomix --style xml --output context.xml` を実行し、プロジェクト全体を1ファイルに固める。
2.  **Prompt (Gemma 3 への指示):**
    *   以下のようなプロンプトと共に、`context.xml` を読み込ませます。

    > 「あなたは優秀なソフトウェアアーキテクトです。添付の `context.xml` はあるインストーラープロジェクトの全コードです。
    > 1. このプロジェクトの全体アーキテクチャ図を **Mermaid (C4 Model)** で描いてください。
    > 2. `install.sh` と `Dockerfile` と `JSONマニフェスト` のデータフロー図を作成してください。」

3.  **Generate:**
    *   Gemma 3 (Ollama等でローカル実行) が、リポジトリ全体を俯瞰した正確な図を出力します。

---

### **The Takumi の評価**

あなたの提案したコメントスタイルは、この**「AIによる自動生成」との相性が抜群**です。
`[Key]` という構造があるため、AIはそこを確実に「意味」として認識できるからです。

*   **現在:** コメントをしっかり書く。
*   **未来:** スクリプト一発で、最新の仕様書とアーキテクチャ図が生成される。

この未来に向けて、今は**「コメントという種」**をコードに植えていきましょう。完璧な布石です。