#!/bin/bash
set -e

# --- テストの本体 ---
echo "--- Testing build_merged_catalog ---"
/app/install.sh

# 成果物の存在確認
if [ ! -f /app/cache/catalogs/custom_nodes_merged.json ]; then
    echo "🔴 ERROR: Merged catalog was not created."
    exit 1
fi

echo "✅ Merged catalog created successfully."
echo "--- All tests passed ---"