## File Tree
_Last updated: 2026-05-26_

```
DockAnchor/
├── DockAnchor/                        # Main app target
│   ├── AppSettings.swift              # User preferences and settings persistence
│   ├── Assets.xcassets                # App icons and image assets
│   ├── ContentView.swift              # Main SwiftUI view (menu bar UI)
│   ├── DisplayIdentifier.swift        # Stable display identity across reconnects
│   ├── DisplayManager.swift           # Display enumeration and management
│   ├── DisplayTypes.swift             # Shared display-related types/models
│   ├── DockAnchor.entitlements        # App sandbox entitlements
│   ├── DockAnchor.xcdatamodeld/       # Core Data model (legacy/unused)
│   │   └── DockAnchor.xcdatamodel
│   ├── DockAnchorApp.swift            # App entry point, menu bar setup
│   ├── DockMonitor.swift              # Monitors display changes, triggers relocation
│   ├── DockRelocator.swift            # Moves the Dock to the target display/position
│   ├── Info.plist                     # App metadata and permissions
│   ├── MouseEventHandler.swift        # Hot corner mouse event monitoring
│   ├── PermissionManager.swift        # Accessibility permission checks
│   ├── Persistence.swift              # Core Data stack (legacy/unused)
│   └── UpdateChecker.swift            # GitHub release update checker
├── DockAnchorTests/
│   └── DockAnchorTests.swift          # Unit tests
├── DockAnchorUITests/
│   ├── DockAnchorUITests.swift        # UI tests
│   └── DockAnchorUITestsLaunchTests.swift
├── Plans/
│   └── refactor-dockmonitor-monolith.md
├── Products/
│   ├── DockAnchor.app
│   ├── DockAnchorTests.xctest
│   └── DockAnchorUITests.xctest
├── architecture.md
├── CLAUDE.md
├── file-tree.md
└── settings.json
```
