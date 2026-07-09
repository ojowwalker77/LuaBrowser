# Sentinel Watchdog Design

Date: 2026-07-09
Status: approved
Branch: `feature/sentinel-watchdog` (based on `dev`)

## Problem

When Phi AI is enabled, the browser launches Sentinel once at startup (`AppController.swift`, gated on `phiAIEnabled`) and never checks on it again. If Sentinel dies mid-session (crash, runner give-up path, internal termination), Phi AI features silently degrade until the next browser cold launch. The browser should supervise Sentinel liveness while Phi AI is enabled and relaunch it when it dies.

## Approach

Hybrid monitoring (chosen over pure polling and pure notification):

- **Primary**: `NSWorkspace.shared.notificationCenter` `didTerminateApplicationNotification`, filtered to the Sentinel bundle ID — immediate reaction, zero polling cost.
- **Backstop**: low-frequency liveness poll (60s) in case a termination notification is ever missed.
- **Debounced recovery**: on a death signal, wait 2s and re-check before launching — Sentinel's own self-relaunch (version guard) has a brief old-exits/new-starts window that must not trigger a duplicate launch. A spurious launch is harmless anyway (`ensureRunning` no-ops when running; Sentinel's single-instance guard aborts duplicates) but the debounce keeps logs clean.

## Component

`Sources/Application/SentinelWatchdog.swift` — `@MainActor final class SentinelWatchdog`, singleton `shared`, all dependencies injectable (mirrors `SentinelVersionGuard` style): `isRunningProvider`, `launcher`, notification center, `now: () -> Date`, `sleep: (TimeInterval) async -> Void`, `logger`, and the tuning knobs (`debounceInterval` 2s, `pollInterval` 60s, `backoffCap` 300s, `stabilityWindow` 600s).

### Relaunch policy (backoff, never give up)

- A death occurring ≥ `stabilityWindow` (10 min) after the last watchdog relaunch resets the attempt counter → relaunch immediately (delay 0).
- Rapid successive deaths (crash loop): delay before relaunch grows 1s → 2s → 4s → … capped at `backoffCap` (5 min). The watchdog never gives up; log-only, no UI.
- Single in-flight recovery: overlapping death signals (notification + poll) collapse into one recovery task.

### Suppression windows (must not resurrect Sentinel)

- `stop()` is called **before** `SentinelHelper.requestTerminationForBrowserUpdate()` in both intentional-shutdown paths:
  - Phi AI disable (`BrowserState+ToggleAI.onAIEnabledChanged(false)`),
  - browser OTA (`AppController+Sparkle.updaterShouldRelaunchApplication`) — otherwise the watchdog would relaunch Sentinel during the Sparkle install, recreating the "Sentinel survives the OTA" bug.
- `start()` is called at browser startup when `phiAIEnabled`, and on Phi AI enable.
- `start()`/`stop()` are idempotent; `stop()` cancels in-flight recovery and the poll task.

## Wiring (whole diff surface)

| File | Change |
| --- | --- |
| `Sources/Application/SentinelWatchdog.swift` | new |
| `Tests/PhiBrowserTests/SentinelWatchdogTests.swift` | new |
| `Sources/Application/AppController.swift` | `SentinelWatchdog.shared.start()` after the existing `phiAIEnabled` launch |
| `Sources/States/BrowserState+ToggleAI.swift` | enable → `start()`; disable → `stop()` before `requestTerminationForBrowserUpdate()` |
| `Sources/Application/AppController+Sparkle.swift` | `stop()` before `requestTerminationForBrowserUpdate()` in `updaterShouldRelaunchApplication` |

## Testing

Unit tests with injected fake clock/sleep/notification-center (style: `SentinelVersionGuardTests`):

1. death signal → debounce → still dead → launch called
2. `stop()` then death signal → no launch
3. death signal → recovered during debounce → no launch
4. rapid successive deaths → recorded backoff delays grow (0, 1, 2, 4 … capped)
5. stability reset: death > 10 min after last relaunch → immediate relaunch (delay 0)
6. poll path discovers dead Sentinel → launch
7. overlapping death signals → single launch

Assertions run against recorded launcher invocations and recorded sleep durations; no real timers.

## Out of scope

- No UI/alerts for crash loops (log-only, per design decision).
- No monitoring when Phi AI is disabled.
- Sentinel-side changes: none.
