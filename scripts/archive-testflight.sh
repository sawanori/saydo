#!/bin/bash
# Release でアーカイブし、App Store Connect にアップロードする（TestFlight 内部配布用）。
# 使い方: SAYDO_TEAM_ID=XXXXXXXXXX scripts/archive-testflight.sh [build-number]
# 署名・アップロードには Xcode にサインインした Apple ID か App Store Connect API キー
# （SAYDO_ASC_KEY_PATH / SAYDO_ASC_KEY_ID / SAYDO_ASC_ISSUER_ID）のどちらかが要る。
# App Store Connect 側に bundle id com.nonturn.saydo の App レコードが先に要る（無ければアップロードが失敗する）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "${SAYDO_TEAM_ID:-}" ]; then
  echo "archive-testflight: SAYDO_TEAM_ID が未設定。" >&2
  exit 5
fi

"$ROOT/scripts/generate-project.sh"

BUILD_NUMBER="${1:-$(date +%Y%m%d%H%M)}"
ARCHIVE="$ROOT/build/Saydo.xcarchive"
EXPORT_DIR="$ROOT/build/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

AUTH_ARGS=()
if [ -n "${SAYDO_ASC_KEY_PATH:-}" ]; then
  AUTH_ARGS=(-authenticationKeyPath "$SAYDO_ASC_KEY_PATH" -authenticationKeyID "$SAYDO_ASC_KEY_ID" -authenticationKeyIssuerID "$SAYDO_ASC_ISSUER_ID")
fi

echo "archive-testflight: team=${SAYDO_TEAM_ID} build=${BUILD_NUMBER}"
xcodebuild archive \
  -project Saydo.xcodeproj \
  -scheme Saydo \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$SAYDO_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# teamID を書き足した ExportOptions を一時的に作る
OPTS="$ROOT/build/ExportOptions.plist"
cp "$ROOT/scripts/ExportOptions-testflight.plist" "$OPTS"
/usr/libexec/PlistBuddy -c "Add :teamID string ${SAYDO_TEAM_ID}" "$OPTS"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}"

echo "archive-testflight: uploaded build ${BUILD_NUMBER}（App Store Connect で処理完了を待つ）"
