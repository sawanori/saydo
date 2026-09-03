#!/bin/bash
# iOS ターゲットをシミュレータ SDK でビルドする。
# シミュレータランタイムが未導入でも通るように generic/platform=iOS Simulator を使う。
# 使い方: scripts/build-ios.sh [scheme]   （既定 Saydo。ほかに SpeechSpike）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${1:-Saydo}"

echo "build-ios: scheme=${SCHEME}"
xcodebuild build \
  -project Saydo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
