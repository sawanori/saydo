#!/bin/bash
# macOS ターゲット（fm-probe）をビルドする。
# 使い方: scripts/build-mac.sh <scheme>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ $# -lt 1 ]; then
  echo "使い方: scripts/build-mac.sh <scheme>   例: scripts/build-mac.sh fm-probe" >&2
  exit 2
fi
SCHEME="$1"

echo "build-mac: scheme=${SCHEME}"
xcodebuild build \
  -project Saydo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
