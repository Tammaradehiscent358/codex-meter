# Architecture

Codex Meter is a SwiftUI/AppKit status-bar application with four small layers:

1. `AppDelegate` owns `NSStatusItem` and `NSPopover` lifecycle.
2. `UsageStore` owns polling, preferences, login-item registration, and low-usage notifications.
3. `CodexAppServerClient` owns one local stdio JSONL session with `codex app-server`.
4. `RateLimitParser` converts versioned app-server payloads into stable UI models.

The client performs the required `initialize` handshake before calling `account/rateLimits/read`. It prefers the `codex` entry in the multi-bucket response and falls back to the backward-compatible single-bucket response. Percentages are clamped to 0–100, and the menu bar displays the lowest remaining percentage across returned windows.

The app intentionally does not consume rate-limit reset credits or expose any write-capable Codex method.
