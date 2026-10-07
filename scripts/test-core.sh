#!/bin/bash
# SaydoCore（純 Swift パッケージ）のテストを macOS で実行し、企画原則の lint を続けて走らせる。
# 使い方: scripts/test-core.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift test --package-path Packages/SaydoCore

"$ROOT/scripts/lint-principles.sh"
