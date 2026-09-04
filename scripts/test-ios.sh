#!/bin/bash
# iOS のユニットテストを、利用可能な iOS 26.x シミュレータで実行する。
# 使い方: scripts/test-ios.sh [scheme]   （既定 Saydo）
# iOS 26.x のシミュレータが 1 台も無い場合は理由を出して exit 2（テストは実行できない）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Saydo.xcodeproj は project.yml からの生成物（コミットしない）。毎回作り直す。
"$ROOT/scripts/generate-project.sh"

SCHEME="${1:-Saydo}"

SELECTED="$(xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

devices = json.load(sys.stdin).get("devices", {})
candidates = []
for runtime, entries in devices.items():
    matched = re.search(r"iOS-26-(\d+)", runtime)
    if not matched:
        continue
    minor = int(matched.group(1))
    for entry in entries:
        if not entry.get("isAvailable", False):
            continue
        name = entry.get("name", "")
        candidates.append((0 if "iPhone" in name else 1, -minor, name, entry["udid"], runtime))
candidates.sort()
if candidates:
    _, _, name, udid, runtime = candidates[0]
    print(f"{udid}\t{name}\t{runtime}")
')"

if [ -z "$SELECTED" ]; then
  echo "test-ios: iOS 26.x の利用可能なシミュレータが見つからない。" >&2
  echo "  導入コマンド: xcodebuild -downloadPlatform iOS（約 8.4 GB の空きが必要）" >&2
  echo "  現在のランタイム一覧:" >&2
  xcrun simctl list runtimes >&2
  exit 2
fi

UDID="$(printf '%s' "$SELECTED" | cut -f1)"
NAME="$(printf '%s' "$SELECTED" | cut -f2)"
RUNTIME="$(printf '%s' "$SELECTED" | cut -f3)"
echo "test-ios: scheme=${SCHEME} device=${NAME} runtime=${RUNTIME} udid=${UDID}"

# 複数の worktree から同時に実行すると 1 台のシミュレータを取り合って install / launch が壊れるため、
# 同じ Mac では 1 つずつ実行する（mkdir による排他。持ち主のプロセスが消えていれば回収する）。
LOCK_DIR="${TMPDIR:-/tmp}/saydo-test-ios.lock"
acquire_lock() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    local owner
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$LOCK_DIR"
      continue
    fi
    if [ "$waited" -eq 0 ]; then
      echo "test-ios: 別の test-ios（pid=${owner:-?}）が実行中。終わるまで待つ（lock=${LOCK_DIR}）"
    fi
    sleep 10
    waited=$((waited + 10))
    if [ "$waited" -ge 3600 ]; then
      echo "test-ios: 60 分待っても lock が解放されない。exit 4" >&2
      exit 4
    fi
  done
  echo $$ > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
}
acquire_lock

xcodebuild test \
  -project Saydo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=${UDID}" \
  CODE_SIGNING_ALLOWED=NO

"$ROOT/scripts/lint-principles.sh"
