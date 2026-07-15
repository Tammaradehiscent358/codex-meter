#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/scripts/build-app.sh" "$ROOT/dist"
STAGE="$(mktemp -d /Applications/.codex-meter-install.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

pkill -x CodexMeter 2>/dev/null || true
ditto --norsrc --noextattr --noqtn --noacl "$ROOT/dist/Codex Meter.app" "$STAGE/Codex Meter.app"
xattr -cr "$STAGE/Codex Meter.app"
codesign --force --deep --sign - "$STAGE/Codex Meter.app"
codesign --verify --deep --strict "$STAGE/Codex Meter.app"

if [[ -d "/Applications/Codex Meter.app" ]]; then
  BACKUP="/Applications/.Codex Meter.previous.app"
  rm -rf "$BACKUP"
  mv "/Applications/Codex Meter.app" "$BACKUP"
  if ! mv "$STAGE/Codex Meter.app" "/Applications/Codex Meter.app"; then
    mv "$BACKUP" "/Applications/Codex Meter.app"
    exit 1
  fi
  rm -rf "$BACKUP"
else
  mv "$STAGE/Codex Meter.app" "/Applications/Codex Meter.app"
fi

codesign --verify --deep --strict "/Applications/Codex Meter.app"
open "/Applications/Codex Meter.app"
echo "Installed and opened /Applications/Codex Meter.app"
