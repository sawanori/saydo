#!/bin/bash
# Saydo.xcodeproj を project.yml から作り直す。
# *.xcodeproj は生成物でコミットしないので、xcodebuild を使う各スクリプトが最初にこれを読み込む。
# xcodegen が無ければ導入方法を出して exit 3。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen > /dev/null 2>&1; then
  echo "generate-project: xcodegen が見つからない。Saydo.xcodeproj は project.yml からの生成物なので、生成せずにビルドはできない。" >&2
  echo "  導入コマンド: brew install xcodegen" >&2
  exit 3
fi

xcodegen generate
