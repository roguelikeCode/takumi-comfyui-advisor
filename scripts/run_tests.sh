#!/bin/bash

# エラー即時脱出、未定義変数エラー、パイプエラー検知
set -euo pipefail

echo "========================================"
echo "🧪 Takumi System: Automated Testing"
echo "========================================"

# 1. install.sh をライブラリとして読み込む（実行はされない）
#    これにより、fetch_external_catalogs などの関数が使えるようになる
source /app/install.sh

# --- Test Case 1: Catalog Fetching ---
echo ">>> [Test 1/3] Fetching external catalogs..."
if fetch_external_catalogs; then
    echo "✅ Fetch success."
else
    echo "🔴 Fetch failed."
    exit 1
fi

# --- Test Case 2: Catalog Merging ---
echo ">>> [Test 2/3] Building merged catalog..."
if build_merged_catalog "custom_nodes"; then
    echo "✅ Merge success."
else
    echo "🔴 Merge failed."
    exit 1
fi

# --- Test Case 3: Artifact Validation ---
echo ">>> [Test 3/3] Validating output JSON..."
TARGET_FILE="/app/cache/catalogs/custom_nodes_merged.json"

# ファイル存在確認
if [ ! -f "$TARGET_FILE" ]; then
    echo "🔴 Error: Output file not found: $TARGET_FILE"
    exit 1
fi

# JSON構文チェック (jqを使って正しいJSONか確認する)
if jq empty "$TARGET_FILE" > /dev/null 2>&1; then
    echo "✅ JSON syntax is valid."
else
    echo "🔴 Error: Invalid JSON format generated."
    exit 1
fi

echo ""
echo "🎉 All tests passed successfully!"
exit 0