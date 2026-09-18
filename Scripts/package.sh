#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="${CODEX_ACCOUNTS_BUILD_DIR:-$PROJECT_DIR/work/build}"
CACHE_DIR="${CODEX_ACCOUNTS_CACHE_DIR:-$PROJECT_DIR/work/cache}"
WORK_DIR="${CODEX_ACCOUNTS_WORK_DIR:-$PROJECT_DIR/work}"
mkdir -p "$OUTPUT_DIR" "$CACHE_DIR" "$WORK_DIR/tmp"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR"
export TMPDIR="$WORK_DIR/tmp"

swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" \
    --cache-path "$CACHE_DIR/swiftpm" --disable-sandbox -c release

APP_DIR="$OUTPUT_DIR/Codex Accounts.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/release/CodexAccounts" "$APP_DIR/Contents/MacOS/CodexAccounts"
strip -S "$APP_DIR/Contents/MacOS/CodexAccounts"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
swift "$PROJECT_DIR/Scripts/MakeIcon.swift" "$WORK_DIR/AppIcon.iconset"
iconutil -c icns "$WORK_DIR/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.codexaccounts.app "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
printf '应用已生成：%s\n' "$APP_DIR"
