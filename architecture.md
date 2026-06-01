# DockAnchor Architecture

## Overview
macOS menu bar app that keeps the Dock anchored to a specific display by intercepting mouse events near dock-trigger zones on non-anchor displays. Also actively relocates the Dock back if it drifts, using synthetic mouse events and a periodic position check.

## Entry Point
- `DockAnchorApp.swift` — `@main` App, `ApplicationDelegate` (lifecycle, auto-start, update check), `MenuBarManager` (NSStatusItem with Combine-driven menu)
- `ContentView.swift` — Main SwiftUI UI: status, display picker, profiles, dock settings

## Core Classes

### `DockMonitor` (coordinator)
`NSObject, ObservableObject` singleton (`DockMonitor.shared`). Owns all `@Published` state and timer/tap properties. Coordinates subsystems via Swift extensions.

**File:** `DockMonitor.swift`
**Properties:** `isActive`, `anchoredDisplay`, `statusMessage`, `availableDisplays`, `anchorDisplayUUID`, `dockPosition`, `isRelocating`, `eventTap`, `permissionCheckTimer`, `hotCornerWatchTimer`, `positionCheckTimer`

### Extension Files

| File | `extension DockMonitor` responsibilities |
|---|---|
| `DisplayTypes.swift` | Shared types: `DockPosition` enum, `DisplayInfo` struct |
| `DisplayIdentifier.swift` | EDID serial extraction, UUID fingerprinting, UUID↔ID lookups |
| `DisplayManager.swift` | Display enumeration, reconfiguration callbacks, approach/trigger point geometry |
| `PermissionManager.swift` | Accessibility permission check/prompt; `startPermissionMonitoring` (2s timer) / `stopPermissionMonitoring` |
| `DockRelocator.swift` | Relocate Dock via synthetic hover+dwell; `isDockOnAnchoredDisplay`; `changeDockPosition`; **`startPositionCheckTimer`** (5 min) / `stopPositionCheckTimer` |
| `DockResizer.swift` | AppleScript-based dock tile size read/write |
| `MouseEventHandler.swift` | CGEvent tap lifecycle (`startMonitoring`/`stopMonitoring`), mouse filter (`shouldBlockDockMovement`), hot corner watch timer |

### `AppSettings`
`ObservableObject` singleton. Persists user preferences via `UserDefaults`: anchor display UUID, profiles, `autoRelocateDock`, hot corner toggle per display. Notifies `DockMonitor` via `NotificationCenter`.

### `DockProfile`
`Codable` value type stored in `AppSettings.profiles`. Fields: `id`, `name`, `anchorDisplayUUID`, `autoActivate`, optional `dockPosition` and `dockTileSize` overrides.

## Key Data Flow

```
Mouse moves near dock edge
  → CGEvent tap (MouseEventHandler)
  → shouldBlockDockMovement → checks anchorDisplayID + hot corner setting
  → if hot corner: startHotCornerDockWatch (polls isDockOnAnchoredDisplay every 1s × 5)
  → if dock-trigger zone: nil (event dropped)

5-minute timer fires (positionCheckTimer)
  → isDockOnAnchoredDisplay? → if false + autoRelocateDock → relocateDockToAnchoredDisplay

Display connect/disconnect
  → CGDisplayRegisterReconfigurationCallback (DisplayManager)
  → updateAvailableDisplays → validateCurrentAnchorDisplay
  → profile auto-activation (findAutoActivateProfile) or anchor restore
  → optional: relocateDockToAnchoredDisplay

User selects anchor display (ContentView / menu bar)
  → AppSettings.selectedDisplayUUID set → .anchorDisplayChanged notification
  → DockMonitor.changeAnchorDisplay(toUUID:) → relocateDockToAnchoredDisplay
```

## Dock Relocation Mechanism
1. Guard: skip if `isRelocating` already true or anchor display not found.
2. Create temporary event tap if not monitoring (blocks real mouse events during sweep).
3. `NSCursor.hide()`, set `isRelocating = true`.
4. Warp cursor past the anchor display's edge (`getPastEdgePoint`), animate 8-step sweep to dock-trigger point (`getDockTriggerPoint`).
5. Pin cursor with `CGAssociateMouseAndMouseCursorPosition(0)`, post 20 synthetic `mouseMoved` events over ~1000ms (macOS dock hover threshold ~500ms).
6. Re-associate cursor, restore to clamped original position, `NSCursor.unhide()`, clear `isRelocating`.

`getSafeEdgeOffset` calculates a midpoint on the dock edge segment not shared with adjacent displays (avoids hot-corner zones at boundaries).

## Dock Detection (`isDockOnAnchoredDisplay`)
1. **visibleFrame heuristic**: compares `NSScreen.visibleFrame` vs `NSScreen.frame`; the screen where the Dock reserves space has a smaller visible frame.
2. **AXUIElement fallback**: queries Dock process window position via Accessibility API.

## Timers

| Timer | Interval | Purpose |
|---|---|---|
| `permissionCheckTimer` | 2s | Verify Accessibility permission and event tap validity while monitoring |
| `hotCornerWatchTimer` | 2s initial → 1s × 5 | Re-anchor after a hot-corner pass lets Dock drift |
| `positionCheckTimer` | 300s | Periodic confirmation Dock is still on anchor display; relocates if not |

## Notifications
| Name | Direction | Meaning |
|---|---|---|
| `.anchorDisplayChanged` | AppSettings → DockMonitor | User selected a different anchor display UUID |
| `.defaultAnchorDisplayChanged` | AppSettings → DockMonitor | Default anchor preference changed |
| `.displaysDidChange` | DockMonitor → UI | Available displays list updated |
| `.dockVisibilityChanged` | AppSettings → ApplicationDelegate | `hideFromDock` toggle changed |
| `.statusIconVisibilityChanged` | AppSettings → MenuBarManager | Status icon toggle changed |

## Threading
| Thread | Responsibilities |
|---|---|
| Main | All UI, NSAppleScript, Timer callbacks, display-change handler |
| Global (userInitiated) | Relocation sweep (sleep loops, CGWarp calls) |
| CGEvent tap (session) | Mouse event interception — returns quickly, dispatches status updates to main |

## Permissions
Requires **Accessibility** (TCC) to create a `CGEvent` tap. Permission loss detected every 2s by `PermissionManager`; stops monitoring if revoked.

## Persistence
- **UserDefaults**: all `AppSettings` properties + profiles as JSON blob.
- **Core Data**: scaffolded (`Persistence.swift`, `DockAnchor.xcdatamodeld`) but not actively used.
- **ServiceManagement**: `SMAppService.mainApp` for login-item registration.

## Display Identification
`DisplayIdentifier` builds a stable fingerprint: `UUID[-SNserial][-Vvendor/model]`. Survives cable swaps and reboots. Stored in `AppSettings.selectedDisplayUUID`, matched against `DockMonitor.anchorDisplayUUID`.
