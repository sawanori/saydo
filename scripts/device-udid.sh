#!/bin/bash
# USB / Wi-Fi で繋がっている iPhone の UDID（xcodebuild の -destination id= と devicectl --device の両方で使える形）を 1 つ返す。
# 使い方: scripts/device-udid.sh   （SAYDO_DEVICE_UDID が設定済みならそれを優先）
set -euo pipefail

if [ -n "${SAYDO_DEVICE_UDID:-}" ]; then
  printf '%s\n' "$SAYDO_DEVICE_UDID"
  exit 0
fi

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT
xcrun devicectl list devices --json-output "$TMP_JSON" > /dev/null 2>&1

python3 - "$TMP_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
devices = data.get("result", {}).get("devices", [])
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("deviceType") != "iPhone":
        continue
    if conn.get("pairingState") != "paired":
        continue
    print(hw.get("udid") or d["identifier"])
    break
else:
    sys.exit(1)
PY
