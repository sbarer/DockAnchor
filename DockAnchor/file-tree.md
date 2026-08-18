## File Tree
_Last updated: 2026-06-13_

```
DockAnchor/
├── DockAnchor/                                 # Main app target (DockAnchorDeluxe)
│   ├── App/
│   │   ├── ApplicationDelegate.swift           # NSApplicationDelegate: lifecycle, startup monitoring/relocation, dock visibility
│   │   ├── MenuBarManager.swift                # NSStatusItem menu bar icon and menu
│   │   └── WindowHiderDelegate.swift           # NSWindowDelegate: hides window on close
│   ├── Models/
│   │   ├── DisplayInfo.swift                   # DisplayInfo struct (id, uuid, frame, name, isPrimary)
│   │   ├── DockPosition.swift                  # DockPosition enum: .bottom, .left, .right
│   │   └── DockProfile.swift                   # Codable profile: anchor UUID, dock position/size overrides, auto-activate
│   ├── Services/
│   │   ├── DisplayService.swift                # Display enumeration, stable UUID fingerprinting, reconfiguration callbacks
│   │   ├── DockCoordinator.swift               # ObservableObject coordinator: owns published state, timers, wires subsystems
│   │   ├── DockRelocationService.swift         # Dock detection (visibleFrame heuristic + AX fallback) and relocation (synthetic cursor sweep)
│   │   ├── DockResizeService.swift             # Dock position/tile size via defaults + NSAppleScript
│   │   ├── MouseTrackingService.swift          # CGEvent tap lifecycle, hot corner detection
│   │   └── PermissionService.swift             # Accessibility permission check and polling
│   ├── Views/
│   │   ├── Display/
│   │   │   ├── AnchorDisplaySection.swift      # Display picker section
│   │   │   ├── DisplayArrangementView.swift    # Visual multi-display arrangement
│   │   │   └── DisplayRectangleView.swift      # Individual display rectangle component
│   │   ├── DockSettings/
│   │   │   └── DockSettingsSection.swift       # Dock position and tile size controls
│   │   ├── Main/
│   │   │   ├── ControlsSection.swift           # Start/stop monitoring controls
│   │   │   └── StatusSection.swift             # Anchor status display
│   │   ├── Profiles/
│   │   │   ├── EditProfileSheet.swift          # Edit existing profile sheet
│   │   │   ├── NewProfileSheet.swift           # Create new profile sheet
│   │   │   ├── ProfileChip.swift               # Profile chip UI component
│   │   │   └── ProfilesSection.swift           # Profile list and management
│   │   ├── Settings/
│   │   │   └── SettingsView.swift              # App settings view
│   │   └── Shared/
│   │       ├── CardStyle.swift                 # Reusable card view modifier
│   │       ├── PermissionHelpSheet.swift       # Accessibility permission help sheet
│   │       └── WindowAccessor.swift            # NSWindow accessor for SwiftUI
│   ├── AppSettings.swift                       # ObservableObject: UserDefaults persistence, profiles, preferences
│   ├── architecture.md
│   ├── Assets.xcassets
│   ├── CLAUDE.md
│   ├── ContentView.swift                       # Root SwiftUI view composed of section views
│   ├── DockAnchor.entitlements
│   ├── DockAnchor.xcdatamodeld/               # Core Data (scaffolded, unused)
│   │   └── DockAnchor.xcdatamodel
│   ├── DockAnchorApp.swift                     # @main App: initialises singletons as @ObservedObject, NSApplicationDelegateAdaptor
│   ├── file-tree.md
│   ├── Persistence.swift                       # Core Data stack (scaffolded, unused)
│   └── UpdateChecker.swift                     # GitHub release update checker
├── DockAnchorTests/
│   ├── Models/
│   │   └── DockProfileTests.swift
│   ├── Services/
│   │   ├── DisplayServiceTests.swift
│   │   ├── DockRelocationServiceTests.swift
│   │   ├── DockResizeServiceTests.swift
│   │   └── MouseTrackingServiceTests.swift
│   ├── Settings/
│   │   └── AppSettingsTests.swift
│   └── DockAnchorTests.swift
├── DockAnchorUITests/
│   ├── DockAnchorUITests.swift
│   └── DockAnchorUITestsLaunchTests.swift
└── Products/
    ├── DockAnchorDeluxe.app
    ├── DockAnchorTests.xctest
    └── DockAnchorUITests.xctest
```
