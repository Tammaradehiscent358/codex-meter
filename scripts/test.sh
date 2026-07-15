#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc \
  "$ROOT/Sources/CodexMeter/RateLimitModels.swift" \
  "$ROOT/Tests/ParserCheck.swift" \
  -o "$TMP/parser-check"
"$TMP/parser-check"

if [[ "${SKIP_LIVE_CODEX_CHECK:-0}" != "1" ]]; then
  swiftc \
    "$ROOT/Sources/CodexMeter/RateLimitModels.swift" \
    "$ROOT/Sources/CodexMeter/CodexAppServerClient.swift" \
    "$ROOT/Tests/LiveCheck.swift" \
    -o "$TMP/live-check"
  "$TMP/live-check"
fi

swift build --package-path "$ROOT"
