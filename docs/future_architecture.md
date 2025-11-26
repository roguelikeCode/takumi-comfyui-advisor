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

3. 

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