# DockAnchor Architecture

## Overview
macOS menu bar app that keeps the Dock anchored to a specific display by intercepting mouse events near dock-trigger zones on non-anchor displays.

## Entry Point
- `DockAnchorApp.swift` — `@main` App, instantiates `DockMonitor.shared`, holds menu bar `MenuBarExtra`
- `ContentView.swift` — Settings UI; uses `DockMonitor` and `AppSettings` as `@ObservedObject`

## Core Classes

### `DockMonitor` (coordinator)
`NSObject, ObservableObject` singleton (`DockMonitor.shared`). Owns all `@Published` state and `private var` properties. Coordinates the subsystems below via extensions.

**File:** `DockMonitor.swift`
**Responsibilities:** init, `setupInitialState`, `setupNotificationObservers`, `changeAnchorDisplay(toUUID:)`, `deinit`

### Extension Files

| File | `extension DockMonitor` responsibilities |
|---|---|
| `DisplayTypes.swift` | Shared types: `DockPosition` enum, `DisplayInfo` struct (top-level, not nested) |
| `DisplayIdentifier.swift` | EDID serial extraction (file-level funcs), UUID fingerprinting, UUID↔ID lookups, flexible UUID matching |
| `DisplayManager.swift` | Enumerate displays, refresh, validate anchor, display config change callbacks (`CGDisplayRegisterReconfigurationCallback`) |
| `PermissionManager.swift` | Accessibility permission check/prompt/monitor; `startPermissionMonitoring` / `stopPermissionMonitoring` |
| `DockRelocator.swift` | Relocate dock via synthetic mouse events, detect dock display, dock trigger/approach points |
| `MouseEventHandler.swift` | CGEvent tap lifecycle (`startMonitoring`/`stopMonitoring`), mouse filter (`shouldBlockDockMovement`), hot corner watch timer |

### `AppSettings`
`ObservableObject` singleton. Persists user preferences via `UserDefaults`: anchor display UUID, profiles, auto-relocate toggle, hot corner toggle per display. Notifies `DockMonitor` via `NotificationCenter`.

## Key Data Flow

```
Mouse moves near dock edge
  → CGEvent tap (MouseEventHandler)
  → shouldBlockDockMovement → checks anchorDisplayID + hot corner setting
  → if hot corner: startHotCornerDockWatch (polls isDockOnAnchoredDisplay every 1s)
  → if blocked: nil (event dropped)

Display connect/disconnect
  → CGDisplayRegisterReconfigurationCallback (DisplayManager)
  → updateAvailableDisplays → validateCurrentAnchorDisplay
  → profile auto-activation or anchor restore (AppSettings)
  → optional: relocateDockToAnchoredDisplay (DockRelocator)
```

## Dock Relocation Mechanism
1. Temporarily create event tap if not monitoring (suppresses user mouse input during relocation)
2. Set `isRelocating = true` — event tap drops all real mouse events
3. Warp cursor to approach point, post synthetic `mouseMoved` events toward dock edge
4. Synthetic events are tagged with `syntheticEventMarker` (so tap lets them through)
5. Restore cursor, clear `isRelocating`

## Notifications
| Name | Direction | Meaning |
|---|---|---|
| `.anchorDisplayChanged` | AppSettings → DockMonitor | User selected a different anchor display |
| `.defaultAnchorDisplayChanged` | AppSettings → DockMonitor | Default anchor setting changed |
| `.displaysDidChange` | DockMonitor → UI | Available displays list updated |

## Permissions
Requires **Accessibility** (TCC) to create a `CGEvent` tap. Permission loss is detected every 2 s by `PermissionManager` and stops monitoring.
