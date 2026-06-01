## File Tree
_Last updated: 2026-06-01_

```
DockAnchor/
├── DockAnchor/                             # Main app target
│   ├── AppSettings.swift                   # User preferences, profile management, UserDefaults persistence
│   ├── Assets.xcassets                     # App icons and image assets
│   ├── ContentView.swift                   # Main SwiftUI UI: status, display picker, profiles, dock settings
│   ├── DisplayIdentifier.swift             # Stable display fingerprinting (UUID + serial number)
│   ├── DisplayManager.swift                # Display enumeration, reconfiguration callbacks, geometry helpers
│   ├── DisplayTypes.swift                  # Shared types: DockPosition enum, DisplayInfo struct
│   ├── DockAnchor.entitlements             # App sandbox entitlements
│   ├── DockAnchor.xcdatamodeld/            # Core Data model (scaffolded, unused)
│   │   └── DockAnchor.xcdatamodel
│   ├── DockAnchorApp.swift                 # App entry, ApplicationDelegate, MenuBarManager
│   ├── DockMonitor.swift                   # Singleton coordinator: published state, timers, tap properties
│   ├── DockRelocator.swift                 # Dock relocation via synthetic mouse events; 5-min position check timer
│   ├── DockResizer.swift                   # Dock tile size read/write via AppleScript + defaults
│   ├── Info.plist                          # App metadata and permissions
│   ├── MouseEventHandler.swift             # CGEvent tap lifecycle, mouse blocking, hot corner watch timer
│   ├── PermissionManager.swift             # Accessibility permission checks and 2s polling timer
│   ├── Persistence.swift                   # Core Data stack (scaffolded, unused)
│   └── UpdateChecker.swift                 # GitHub release update checker
├── DockAnchorTests/
│   └── DockAnchorTests.swift               # Unit tests
├── DockAnchorUITests/
│   ├── DockAnchorUITests.swift             # UI tests
│   └── DockAnchorUITestsLaunchTests.swift
├── Plans/
│   └── refactor-dockmonitor-monolith.md
├── Products/
│   ├── DockAnchor.app
│   ├── DockAnchorTests.xctest
│   └── DockAnchorUITests.xctest
├── architecture.md
├── CLAUDE.md
└── file-tree.md
```
