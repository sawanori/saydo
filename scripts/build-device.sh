#!/bin/bash
# 繋いだ iPhone に Saydo（または指定スキーム）をビルドしてインストールし、起動する。
# 使い方: SAYDO_TEAM_ID=XXXXXXXXXX scripts/build-device.sh [scheme] [--no-launch]
# 署名は Automatic。Xcode にサインインした Apple ID か、App Store Connect API キー
# （SAYDO_ASC_KEY_PATH / SAYDO_ASC_KEY_ID / SAYDO_ASC_ISSUER_ID）のどちらかが要る。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "${SAYDO_TEAM_ID:-}" ]; then
  echo "build-device: SAYDO_TEAM_ID（Apple Developer のチーム ID、10 文字）が未設定。実機の署名にはチームが要る。" >&2
  echo "  例: SAYDO_TEAM_ID=ABCDE12345 scripts/build-device.sh" >&2
  exit 5
fi

"$ROOT/scripts/generate-project.sh"

SCHEME="${1:-Saydo}"
LAUNCH=1
if [ "${2:-}" = "--no-launch" ]; then LAUNCH=0; fi

UDID="$("$ROOT/scripts/device-udid.sh")" || {
  echo "build-device: ペアリング済みの iPhone が見つからない（xcrun devicectl list devices）。" >&2
  exit 6
}
echo "build-device: scheme=${SCHEME} team=${SAYDO_TEAM_ID} device=${UDID}"

DERIVED="$ROOT/build/device"
AUTH_ARGS=()
if [ -n "${SAYDO_ASC_KEY_PATH:-}" ]; then
  AUTH_ARGS=(-authenticationKeyPath "$SAYDO_ASC_KEY_PATH" -authenticationKeyID "$SAYDO_ASC_KEY_ID" -authenticationKeyIssuerID "$SAYDO_ASC_ISSUER_ID")
fi

xcodebuild build \
  -project Saydo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=${UDID}" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${AUTH_ARGS[@]}" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$SAYDO_TEAM_ID"

APP="$(find "$DERIVED/Build/Products/Debug-iphoneos" -maxdepth 1 -name "${SCHEME}.app" | head -1)"
if [ -z "$APP" ]; then
  echo "build-device: ${SCHEME}.app が見つからない（$DERIVED/Build/Products/Debug-iphoneos）。" >&2
  exit 7
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

echo "build-device: install ${APP}"
xcrun devicectl device install app --device "$UDID" "$APP"

if [ "$LAUNCH" -eq 1 ]; then
  echo "build-device: launch ${BUNDLE_ID}"
  xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"
fi
