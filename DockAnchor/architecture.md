# DockAnchor Architecture

## Overview
macOS menu bar app (DockAnchorDeluxe) that keeps the Dock anchored to a specific display by intercepting mouse events near dock-trigger zones on non-anchor displays. Actively relocates the Dock back if it drifts using synthetic mouse events, with a periodic position check and hot-corner recovery.

## Entry Points
- `DockAnchorApp.swift` — `@main` App; initialises all singletons as `@ObservedObject`; registers `ApplicationDelegate`
- `ApplicationDelegate.swift` — `NSApplicationDelegate`; startup sequence: permission check → `changeAnchorDisplay` → `startMonitoring` (+1s) → `relocateDock` (+1.5s, if `autoRelocateDock`)
- `ContentView.swift` — Root SwiftUI view composed of section views

## Services

### `DockCoordinator` (coordinator)
`ObservableObject` singleton. Owns all `@Published` state. Wires subsystem callbacks and drives all high-level logic.

**Published:** `isActive`, `statusMessage`, `anchoredDisplayName`, `needsPermissionReset`, `displays`
**State:** `anchorDisplayUUID`, `dockPosition`, `isDockAnchored`
**Timers:** `positionCheckTimer` (300s), `hotCornerWatchTimer` (1s repeating, max 5 attempts)

### `DockRelocationService`
`@unchecked Sendable` singleton. Detects dock position and performs relocation.

- **`detectCurrentDockState()`** — Iterates `NSScreen.screens`, computes per-screen insets (`vf.minY - f.minY`, etc.), returns the screen with the **maximum** inset if > 25px. Falls back to AX API (`currentDockDisplayIDViaAX`). **Must be called on main thread** (`NSScreen.screens` is not thread-safe).
- **`isDockOnCorrectDisplay(_:dockPosition:)`** — Calls `detectCurrentDockState()` first; falls back to `currentDockDisplayID` (visibleFrame + AX). Called via `MainActor.run` from `relocate()`.
- **`relocate(to:dockPosition:)`** — `async`; checks `isDockOnCorrectDisplay` on `MainActor`, then dispatches cursor sweep to `DispatchQueue.global(qos: .userInitiated)`.
- **Relocation sweep:** hide cursor → warp past edge → 8-step synthetic `mouseMoved` sweep to trigger point → dwell 20 × 50ms at edge → restore cursor → unhide.
- **`safeEdgeOffset`** — Finds the midpoint of the largest free segment on the dock edge not covered by adjacent displays.

### `DisplayService`
`ObservableObject` singleton. Enumerates displays via `CGGetActiveDisplayList`. Builds stable fingerprint UUIDs: `UUID[-SNserial][-Vvendor/model]`. Registers `CGDisplayRegisterReconfigurationCallback` and notifies `DockCoordinator` via callbacks.

### `DockResizeService`
Reads/writes dock position and tile size using `defaults` CLI and `NSAppleScript`.

### `MouseTrackingService`
Manages the `CGEvent` tap. Detects hot corners (cursor within 15px of screen corner). Fires `onHotCornerDetected` callback → `DockCoordinator.startHotCornerWatch()`.

### `PermissionService`
Polls `AXIsProcessTrusted()` at a configurable interval. Fires `onRevoked` if permission lost while monitoring.

## Key Data Flow

```
App launch
  → DockCoordinator.setupInitialState() → refreshAnchoredState() → detectCurrentDockState()
  → ApplicationDelegate: changeAnchorDisplay → startMonitoring (+1s) → relocateDock (+1.5s)

System sleep
  → NSWorkspace.willSleepNotification → ApplicationDelegate → coordinator.handleSystemSleep()
  → stopMonitoring() (tears down event tap, timers, permission polling)

System wake
  → NSWorkspace.didWakeNotification → ApplicationDelegate (2s delay)
  → coordinator.handleSystemWake() → stopMonitoring() → startMonitoring (+1s) → relocateDock (+1.5s)

Mouse moves near dock edge
  → CGEvent tap (MouseTrackingService)
  → hot corner detected → onHotCornerDetected → startHotCornerWatch
  → hotCornerTick every 1s: isDockOnCorrectDisplay? → if false → relocateDock (max 5 attempts)

Space switch (activeSpaceDidChangeNotification)
  → debounced 0.5s DispatchWorkItem → isDockOnCorrectDisplay? → if false → relocateDock

600s timer fires (positionCheckTimer, safety-net)
  → isDockOnCorrectDisplay? → if false + autoRelocateDock → relocateDock

Display connect/disconnect
  → CGDisplayRegisterReconfigurationCallback (DisplayService)
  → onDisplayAdded/Removed → DockCoordinator.handleDisplay*
  → profile auto-activation or anchor restore → optional relocateDock

User selects anchor display
  → AppSettings.selectedDisplayUUID → .anchorDisplayChanged notification
  → DockCoordinator.changeAnchorDisplay(toUUID:)

com.apple.dock.refresh notification
  → DockCoordinator updates dockPosition from detectCurrentDockState / profile / defaults
  → refreshAnchoredState()
```

## Dock Detection Algorithm
1. Iterate `NSScreen.screens` (main thread only), compute three insets per screen:
   - `bottomInset = vf.minY - f.minY`
   - `leftInset = vf.minX - f.minX`
   - `rightInset = f.maxX - vf.maxX`
2. Track the screen+direction with the **maximum** inset across all screens.
3. Accept only if max inset > **25px** (dock minimum height; excludes spurious display-arrangement insets).
4. If no screen qualifies, fall back to `currentDockDisplayIDViaAX()`.

## Timers

| Timer | Interval | Purpose |
|---|---|---|
| `PermissionService` poll | configurable (5s while monitoring) | Detect Accessibility permission revocation |
| `hotCornerWatchTimer` | 2s initial delay → 1s × 5 | Re-anchor after hot-corner pass moves Dock |
| `positionCheckTimer` | 600s | Safety-net periodic check; primary trigger is `activeSpaceDidChangeNotification` |

## Notifications

| Name | Direction | Meaning |
|---|---|---|
| `.anchorDisplayChanged` | AppSettings → DockCoordinator | User selected a different anchor display UUID |
| `.defaultAnchorDisplayChanged` | AppSettings → DockCoordinator | Default anchor preference changed |
| `.dockVisibilityChanged` | AppSettings → ApplicationDelegate | `hideFromDock` toggle changed |
| `.statusIconVisibilityChanged` | AppSettings → MenuBarManager | Status icon toggle changed |
| `NSWorkspace.willSleepNotification` | System → ApplicationDelegate | System about to sleep — stops monitoring |
| `NSWorkspace.didWakeNotification` | System → ApplicationDelegate | System woke — restarts monitoring after 2s |
| `NSWorkspace.activeSpaceDidChangeNotification` | System → DockCoordinator | Space switch — debounced 0.5s position check |

## Threading

| Thread | Responsibilities |
|---|---|
| Main | All UI, NSAppleScript, Timer callbacks, display-change handler, `NSScreen.screens` access |
| Global (userInitiated) | Relocation sweep (sleep loops, CGWarp, CGEvent post) |
| CGEvent tap (session) | Mouse event interception — lightweight, dispatches to main |

**Critical:** `NSScreen.screens` and `NSScreen.visibleFrame` must be called on the main thread. `isDockOnCorrectDisplay` and `detectCurrentDockState` are always dispatched via `MainActor.run` or `DispatchQueue.main.sync` when called from async/background contexts.

## AppSettings (Persistence)

`ObservableObject` singleton. Key properties:
- `selectedDisplayUUID: String` — anchor display fingerprint
- `autoRelocateDock: Bool` — enable startup + periodic relocation (default: `true`)
- `runInBackground: Bool` — auto-start monitoring on launch (default: `true`)
- `hideFromDock: Bool` — hide app from Dock (default: `true`)
- `profiles: [DockProfile]` — per-display dock configuration profiles

Persisted via **UserDefaults**. **Core Data** is scaffolded but unused. **ServiceManagement** (`SMAppService.mainApp`) for login item.

## Display Identification

`DisplayService.createStableDisplayFingerprint` builds: `UUID[-SNserial][-Vvendor/model]`. Survives cable swaps and reboots. Matched with fuzzy `baseUUID` stripping (removes `-SN`/`-V` suffix) to tolerate minor fingerprint drift between sessions.
