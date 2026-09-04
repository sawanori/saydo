#!/bin/bash
# 企画原則の機械チェック。
# 1) 禁止 API（ネットワーク・並行性警告の握りつぶし）を見つけたら exit 1。
# 2) *Copy.swift（DialogueCopy / NotificationCopy / InsightCopy など）以外の日本語文字列リテラルを警告として列挙する（exit code には影響しない）。
# 走査対象は App/ と Packages/*/Sources のみ。Tests と Spikes は対象外。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LIST="$(mktemp -t saydo-lint)"
trap 'rm -f "$LIST"' EXIT

find App Packages -type f -name '*.swift' 2>/dev/null \
  | sed 's|^\./||' \
  | grep -vE '(^|/)Tests/' \
  | grep -E '^(App/|Packages/[^/]+/Sources/)' \
  | sort > "$LIST"

COUNT=$(wc -l < "$LIST" | tr -d ' ')
echo "lint-principles: 対象 ${COUNT} ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）"

FAIL=0

check() {
  local label="$1"
  local pattern="$2"
  local hits
  [ "$COUNT" -eq 0 ] && return 0
  hits=$(tr '\n' '\0' < "$LIST" | xargs -0 grep -nE -- "$pattern" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "NG: ${label}"
    printf '%s\n' "$hits" | sed 's/^/    /'
    FAIL=1
  fi
}

check "ネットワーク API（URLSession）" 'URLSession'
check "ネットワークフレームワーク（import Network）" '^[[:space:]]*import[[:space:]]+Network([[:space:]]|$)'
check "Swift 6 並行性警告の握りつぶし（@unchecked Sendable）" '@unchecked[[:space:]]+Sendable'
check "Swift 6 並行性警告の握りつぶし（nonisolated(unsafe)）" 'nonisolated\([[:space:]]*unsafe[[:space:]]*\)'

if [ "$COUNT" -gt 0 ]; then
  python3 - "$LIST" <<'PY'
import re
import sys

literal = re.compile(r'"(?:[^"\\\n]|\\.)*"')
japanese = re.compile(r'[぀-ゟ゠-ヿ一-鿿]')

with open(sys.argv[1], encoding="utf-8") as handle:
    paths = [line.strip() for line in handle if line.strip()]

warnings = []
for path in paths:
    # 文言は *Copy.swift に集約する規約。名前がそれで終わるファイルは対象外。
    if path.rsplit("/", 1)[-1].endswith("Copy.swift"):
        continue
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.readlines()
    except OSError as error:
        print(f"    (読めない: {path}: {error})")
        continue
    for number, line in enumerate(lines, start=1):
        if line.lstrip().startswith("//"):
            continue
        for match in literal.finditer(line):
            if japanese.search(match.group(0)):
                warnings.append(f"    {path}:{number}: {match.group(0)}")
                break

if warnings:
    print("WARN: *Copy.swift 以外に日本語の文字列リテラルがある（文言は Copy に集約する）")
    for warning in warnings:
        print(warning)
PY
fi

if [ "$FAIL" -ne 0 ]; then
  echo "lint-principles: FAIL"
  exit 1
fi

echo "lint-principles: OK"
exit 0
