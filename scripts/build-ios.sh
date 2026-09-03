#!/bin/bash
# iOS ターゲットをシミュレータ SDK でビルドする。
# 通常は generic/platform=iOS Simulator を使う。
# iOS 26.x のシミュレータランタイムが未導入で destination を解決できない環境では、
# destination を使わない -target 形式（コンパイルとリンクのみ）へ自動で切り替える。
# 使い方: scripts/build-ios.sh [scheme]   （既定 Saydo。ほかに SpeechSpike）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${1:-Saydo}"

echo "build-ios: scheme=${SCHEME}"

has_simulator_destination() {
  xcodebuild -project Saydo.xcodeproj -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | awk '/Available destinations/{found=1} found' \
    | grep -q 'platform:iOS Simulator'
}

if has_simulator_destination; then
  xcodebuild build \
    -project Saydo.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
else
  echo "build-ios: 注意 — iOS シミュレータのランタイムが未導入で generic/platform=iOS Simulator を解決できない。"
  echo "build-ios: destination を使わず -target ${SCHEME} でビルドする（コンパイルとリンクだけの検証。実行はできない）。"
  echo "build-ios: 解消するには空き容量を 9 GB 以上確保して xcodebuild -downloadPlatform iOS を実行する。"
  xcodebuild build \
    -project Saydo.xcodeproj \
    -target "$SCHEME" \
    -configuration Debug \
    -sdk iphonesimulator \
    CODE_SIGNING_ALLOWED=NO
fi
