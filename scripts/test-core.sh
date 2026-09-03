#!/bin/bash
# SaydoCore と SaydoAI（純 Swift パッケージ）のテストを macOS で実行し、企画原則の lint を続けて走らせる。
# 使い方: scripts/test-core.sh
#
# SaydoAI の結合テストは Apple Intelligence が有効なときだけ走る（無効なら XCTSkip）。
# 有効な Mac では実際にオンデバイス LLM を呼ぶため 1 分前後かかる。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift test --package-path Packages/SaydoCore

swift test --package-path Packages/SaydoAI

"$ROOT/scripts/lint-principles.sh"
