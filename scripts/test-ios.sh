#!/bin/bash
# iOS のユニットテストを、利用可能な iOS 26.x シミュレータで実行する。
# 使い方: scripts/test-ios.sh [scheme]   （既定 Saydo）
# iOS 26.x のシミュレータが 1 台も無い場合は理由を出して exit 2（テストは実行できない）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

xcodebuild test \
  -project Saydo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=${UDID}" \
  CODE_SIGNING_ALLOWED=NO

"$ROOT/scripts/lint-principles.sh"
