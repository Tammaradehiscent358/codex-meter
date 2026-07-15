#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="${1:-$ROOT/dist}"
FINAL_APP="$OUTPUT/Codex Meter.app"
STAGE="$(mktemp -d)"
APP="$STAGE/Codex Meter.app"
trap 'rm -rf "$STAGE"' EXIT

cd "$ROOT"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ROOT/.build-arm64"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$ROOT/.build-x86_64"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create \
  "$ROOT/.build-arm64/arm64-apple-macosx/release/CodexMeter" \
  "$ROOT/.build-x86_64/x86_64-apple-macosx/release/CodexMeter" \
  -output "$APP/Contents/MacOS/CodexMeter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$FINAL_APP"
mkdir -p "$OUTPUT"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$FINAL_APP"
xattr -cr "$FINAL_APP"
codesign --force --deep --sign - "$FINAL_APP"
codesign --verify --deep --strict "$FINAL_APP"
echo "$FINAL_APP"
