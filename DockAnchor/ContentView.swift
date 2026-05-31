//
//  ContentView.swift
//  DockAnchor
//
//  Created by Bradley Wyatt on 7/2/25.
//

import SwiftUI
import CoreData

private func getAppVersion() -> String {
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        return version
    }
    return "1.3"
}

// MARK: - Display Arrangement View
struct DisplayArrangementView: View {
    let displays: [DisplayInfo]
    @Binding var selectedDisplayUUID: String
    var maxHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            let layout = calculateLayout(containerSize: geometry.size)

            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let frame = layout.scaledFrames[display.id] ?? .zero

                    DisplayRectangleView(
                        display: display,
                        isSelected: display.uuid == selectedDisplayUUID,
                        size: CGSize(width: frame.width, height: frame.height)
                    )
                    .offset(x: frame.minX, y: frame.minY)
                    .onTapGesture {
                        selectedDisplayUUID = display.uuid
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(height: maxHeight)
    }

    private func calculateLayout(containerSize: CGSize) -> DisplayLayout {
        guard !displays.isEmpty else {
            return DisplayLayout(scaledFrames: [:], scale: 1.0)
        }

        // Calculate bounding box of all displays
        let minX = displays.map { $0.frame.minX }.min() ?? 0
        let minY = displays.map { $0.frame.minY }.min() ?? 0
        let maxX = displays.map { $0.frame.maxX }.max() ?? 0
        let maxY = displays.map { $0.frame.maxY }.max() ?? 0

        let totalWidth = maxX - minX
        let totalHeight = maxY - minY

        guard totalWidth > 0 && totalHeight > 0 else {
            return DisplayLayout(scaledFrames: [:], scale: 1.0)
        }

        // Calculate scale to fit in container with padding
        let padding: CGFloat = 10
        let availableWidth = containerSize.width - padding * 2
        let availableHeight = containerSize.height - padding * 2

        let scaleX = availableWidth / totalWidth
        let scaleY = availableHeight / totalHeight
        let scale = min(scaleX, scaleY)

        // Calculate scaled frames centered in container
        let scaledTotalWidth = totalWidth * scale
        let scaledTotalHeight = totalHeight * scale
        let offsetX = (containerSize.width - scaledTotalWidth) / 2
        let offsetY = (containerSize.height - scaledTotalHeight) / 2

        var scaledFrames: [CGDirectDisplayID: CGRect] = [:]

        for display in displays {
            let x = (display.frame.minX - minX) * scale + offsetX
            let y = (display.frame.minY - minY) * scale + offsetY
            let width = display.frame.width * scale
            let height = display.frame.height * scale

            scaledFrames[display.id] = CGRect(x: x, y: y, width: width, height: height)
        }

        return DisplayLayout(scaledFrames: scaledFrames, scale: scale)
    }

    struct DisplayLayout {
        let scaledFrames: [CGDirectDisplayID: CGRect]
        let scale: CGFloat
    }
}

struct DisplayRectangleView: View {
    @Environment(\.colorScheme) var colorScheme
    let display: DisplayInfo
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            // Display rectangle with glass material
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.5) : Color.primary.opacity(0.2)), lineWidth: isSelected ? 2 : 1)

            // Display name
            VStack(spacing: 1) {
                Text(displayLabel)
                    .font(.system(size: fontSize))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : (colorScheme == .dark ? .white : .secondary))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)

                if display.isPrimary {
                    Text("(Primary)")
                        .font(.system(size: max(fontSize - 2, 7)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(4)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private var displayLabel: String {
        // Shorten the display name for the visual
        let name = display.name
            .replacingOccurrences(of: " (Primary)", with: "")
            .replacingOccurrences(of: "Built-in ", with: "")
            .replacingOccurrences(of: " Display", with: "")
        return name
    }

    private var fontSize: CGFloat {
        // Adjust font size based on rectangle size
        let minDimension = min(size.width, size.height)
        if minDimension < 40 {
            return 8
        } else if minDimension < 60 {
            return 9
        } else {
            return 10
        }
    }
}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Profile Chip View
struct ProfileChip: View {
    let profile: DockProfile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if profile.autoActivate {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(isActive ? .white.opacity(0.8) : .orange)
            }

            Text(profile.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .primary)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .white.opacity(0.8) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thickMaterial)
            }
        }
        .overlay {
            if !isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onEdit() }
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - New Profile Sheet
struct NewProfileSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var profileName = ""
    @State private var autoActivate = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Profile")
                .font(.headline)

            TextField("Profile Name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            Toggle("Auto-activate when display connects", isOn: $autoActivate)
                .font(.callout)
                .toggleStyle(.switch)

            Text("This profile will save your current anchor display setting.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let profile = appSettings.createProfile(name: profileName, autoActivate: autoActivate)
                    appSettings.switchToProfile(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.background)
        .onAppear { isNameFocused = true }
    }
}

// MARK: - Edit Profile Sheet
struct EditProfileSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) var dismiss
    let profile: DockProfile
    @State private var profileName: String
    @State private var autoActivate: Bool
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    init(profile: DockProfile) {
        self.profile = profile
        _profileName = State(initialValue: profile.name)
        _autoActivate = State(initialValue: profile.autoActivate)
    }

    private var isActive: Bool {
        appSettings.activeProfileID == profile.id
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Profile")
                .font(.headline)

            TextField("Profile Name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            Divider()

            Toggle("Auto-activate when display connects", isOn: $autoActivate)
                .font(.callout)
                .toggleStyle(.switch)

            Divider()

            Button(action: {
                if isActive {
                    appSettings.deactivateProfile()
                    dismiss()
                } else {
                    activateWithCurrentEdits()
                }
            }) {
                Label(
                    isActive ? "Deactivate Profile" : "Activate Profile",
                    systemImage: isActive ? "stop.circle" : "play.circle"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isActive ? .orange : .accentColor)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }

                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.background)
        .onAppear { isNameFocused = true }
        .confirmationDialog(
            "Delete \"\(profile.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appSettings.deleteProfile(profile)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func saveProfile() {
        var updated = profile
        updated.name = profileName
        updated.autoActivate = autoActivate
        appSettings.updateProfile(updated)
    }

    private func activateWithCurrentEdits() {
        var updated = profile
        updated.name = profileName
        updated.autoActivate = autoActivate
        appSettings.updateProfile(updated)
        appSettings.switchToProfile(updated)
        dismiss()
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var dockMonitor: DockMonitor
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingSettings = false
    @State private var showingNewProfile = false
    @State private var editingProfile: DockProfile?
    @State private var newProfileName = ""
    @State private var showingPermissionHelp = false
    @State private var liveDockPosition: DockPosition = .bottom
    @State private var liveDockTileSize: Double = 48
    @State private var originalDockPosition: DockPosition = .bottom
    @State private var originalDockTileSize: Double = 48
    @State private var dockChangesPending: Bool = false

    private var statusColor: Color {
        if dockMonitor.statusMessage.contains("Blocked") {
            return .red
        } else if dockMonitor.isActive {
            return .green
        } else {
            return .primary
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("DockAnchor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Keep your dock anchored to one display")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            Divider()
            
            // Status Section
            VStack(spacing: 12) {
                HStack {
                    // Check if we just blocked a dock movement attempt
                    if dockMonitor.statusMessage.contains("Blocked") {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                    } else {
                        Circle()
                            .fill(dockMonitor.isActive ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                    }

                    Text(dockMonitor.statusMessage)
                        .font(.headline)
                        .foregroundColor(statusColor)

                    Spacer()
                }

                if dockMonitor.needsPermissionReset || dockMonitor.statusMessage.lowercased().contains("permission") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Accessibility permission required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Help") {
                            showingPermissionHelp = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                } else if !dockMonitor.isActive {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Dock movement protection is disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .cardStyle()

            // Control Buttons
            HStack(spacing: 16) {
                Button(action: {
                    if dockMonitor.isActive {
                        dockMonitor.stopMonitoring()
                    } else {
                        dockMonitor.startMonitoring()
                    }
                }) {
                    HStack {
                        Image(systemName: dockMonitor.isActive ? "stop.circle" : "play.circle")
                        Text(dockMonitor.isActive ? "Stop Protection" : "Start Protection")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(dockMonitor.isActive ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                
                Button(action: {
                    showingSettings = true
                }) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            
            Divider()
            
            // Display Information & Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Anchor Display")
                    .font(.headline)

                // Visual Display Arrangement
                DisplayArrangementView(
                    displays: dockMonitor.availableDisplays,
                    selectedDisplayUUID: $appSettings.selectedDisplayUUID,
                    maxHeight: 100
                )
                .padding(.vertical, 4)

                // Selected display info
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text("Anchored to: \(dockMonitor.anchoredDisplay)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text("Click a display to anchor the dock there")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .cardStyle()

            // Profiles Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Profiles")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingNewProfile = true }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Create new profile")
                }

                if appSettings.profiles.isEmpty {
                    Text("No profiles yet. Create one to save your current display setup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appSettings.profiles) { profile in
                                ProfileChip(
                                    profile: profile,
                                    isActive: appSettings.activeProfileID == profile.id,
                                    onEdit: { editingProfile = profile },
                                    onDelete: { appSettings.deleteProfile(profile) }
                                )
                            }
                        }
                    }
                }
            }
            .cardStyle()

            // Dock Settings Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dock")
                        .font(.headline)
                    if let profile = appSettings.activeProfile {
                        Text("· \(profile.name)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Text("Position")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { liveDockPosition },
                        set: { newValue in
                            print("[DockSettings] position picker → \(newValue.rawValue)")
                            liveDockPosition = newValue
                            dockChangesPending = true
                            DockMonitor.shared.applyDockSettings(position: newValue, tileSize: nil)
                        }
                    )) {
                        ForEach(DockPosition.allCases, id: \.self) { pos in
                            Text(pos.label).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                HStack {
                    Text("Size")
                        .font(.callout)
                    Spacer()
                    Text("\(Int(liveDockTileSize))%")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                Slider(value: $liveDockTileSize, in: 5...55, step: 5) { editing in
                    print("[DockSettings] size slider editing=\(editing), current value=\(Int(liveDockTileSize))%")
                    if !editing {
                        dockChangesPending = true
                        DockMonitor.shared.applyDockSettings(position: nil, tileSize: Int(liveDockTileSize))
                    }
                }

                if dockChangesPending {
                    HStack {
                        Button("Revert") {
                            liveDockPosition = originalDockPosition
                            liveDockTileSize = originalDockTileSize
                            DockMonitor.shared.applyDockSettings(
                                position: originalDockPosition,
                                tileSize: Int(originalDockTileSize)
                            )
                            dockChangesPending = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if appSettings.activeProfile != nil {
                            Button("Save to Profile") {
                                saveDockSettingsToActiveProfile()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .cardStyle()
        }
        .padding()
        .frame(width: 420, height: 820)
        .background(.background)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(isPresented: $showingNewProfile) {
            NewProfileSheet()
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(item: $editingProfile) { profile in
            EditProfileSheet(profile: profile)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(isPresented: $showingPermissionHelp) {
            PermissionHelpSheet(dockMonitor: dockMonitor)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .onAppear {
            // Check permissions on startup and show help if not granted
            let hasPermissions = dockMonitor.requestAccessibilityPermissions()
            if !hasPermissions {
                // Small delay to let the UI appear first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingPermissionHelp = true
                }
                // Don't perform any operations that require accessibility permissions
                return
            }
            // Update available displays
            dockMonitor.updateAvailableDisplays()
            // Set the anchor display from settings (using UUID for stable identification)
            dockMonitor.changeAnchorDisplay(toUUID: appSettings.selectedDisplayUUID)
            initDockState()
        }
        .onChange(of: appSettings.activeProfileID) { _, _ in
            initDockState()
        }
        .onChange(of: appSettings.selectedDisplayUUID) { oldValue, newValue in
            dockMonitor.changeAnchorDisplay(toUUID: newValue)
            // Auto-move dock to the newly selected display if enabled
            if appSettings.autoRelocateDock && oldValue != newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dockMonitor.relocateDockToAnchoredDisplay()
                }
            }
        }
    }

    private func initDockState() {
        // Read actual system state via `defaults read` (same mechanism as existing dock detection)
        let systemPosition = DockMonitor.readCurrentDockPosition()
        let systemSize = Double(DockMonitor.readCurrentDockTileSize())

        if let profile = appSettings.activeProfile {
            liveDockPosition = profile.dockPosition ?? systemPosition
            liveDockTileSize = Double(profile.dockTileSize ?? Int(systemSize))
        } else {
            liveDockPosition = systemPosition
            liveDockTileSize = systemSize
        }
        originalDockPosition = liveDockPosition
        originalDockTileSize = liveDockTileSize
        dockChangesPending = false
    }

    private func saveDockSettingsToActiveProfile() {
        guard var profile = appSettings.activeProfile else { return }
        profile.dockPosition = liveDockPosition
        profile.dockTileSize = Int(liveDockTileSize)
        appSettings.updateProfile(profile)
        originalDockPosition = liveDockPosition
        originalDockTileSize = liveDockTileSize
        dockChangesPending = false
    }

}

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var dockMonitor: DockMonitor
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
            VStack(spacing: 10) {
                // Startup & Background
                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup & Background")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack {
                        Text("Start at Login").font(.callout)
                        Spacer()
                        Toggle("", isOn: $appSettings.startAtLogin)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    HStack {
                        Text("Run in Background").font(.callout)
                        Spacer()
                        Toggle("", isOn: $appSettings.runInBackground)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Dock Behavior
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dock Behavior")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack {
                        Text("Auto-Move Dock").font(.callout)
                        Spacer()
                        Toggle("", isOn: $appSettings.autoRelocateDock)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    HStack {
                        Text("Default Anchor")
                            .font(.callout)
                        Spacer()
                        Picker("", selection: $appSettings.defaultAnchorDisplay) {
                            ForEach(DefaultAnchorDisplay.allCases, id: \.self) { display in
                                Text(display.rawValue).tag(display)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    Text("Used when anchor display is unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Hot Corners
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hot Corners")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("When enabled, corner areas are excluded from edge blocking so macOS hot corners still fire.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(dockMonitor.availableDisplays) { display in
                        HStack {
                            Text(display.name).font(.callout)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appSettings.isHotCornersPreserved(forDisplayUUID: display.uuid) },
                                set: { appSettings.setHotCornersPreserved($0, forDisplayUUID: display.uuid) }
                            ))
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Interface
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interface")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack {
                        Text("Show Menu Bar Icon").font(.callout)
                        Spacer()
                        Toggle("", isOn: $appSettings.showStatusIcon)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    HStack {
                        Text("Hide from Dock").font(.callout)
                        Spacer()
                        Toggle("", isOn: $appSettings.hideFromDock)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    HStack {
                        Text("Theme")
                            .font(.callout)
                        Spacer()
                        Picker("", selection: $appSettings.appTheme) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Display Arrangement
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Arrangement")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    DisplayArrangementView(
                        displays: dockMonitor.availableDisplays,
                        selectedDisplayUUID: $appSettings.selectedDisplayUUID,
                        maxHeight: 60
                    )
                    Text("\(dockMonitor.availableDisplays.count) display(s) detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Footer
                VStack(spacing: 4) {
                    Button(action: {
                        if let url = URL(string: "https://buymeacoffee.com/bwya77") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("☕")
                            Text("Buy Me a Coffee")
                        }
                    }
                    .buttonStyle(.link)

                    Text("Version \(getAppVersion())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            }
        }
        .frame(width: 420, height: 680)
        .background(.background)
        .onAppear {
            dockMonitor.updateAvailableDisplays()
        }
    }
}

struct PermissionHelpSheet: View {
    @ObservedObject var dockMonitor: DockMonitor
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Accessibility Permission")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 16) {
                Text("DockAnchor requires Accessibility permission to monitor mouse movement and keep your dock anchored.")
                    .font(.body)

                Divider()

                Text("How to enable:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Click \"Open Accessibility Settings\" below", systemImage: "1.circle.fill")
                    Label("Find DockAnchor in the list", systemImage: "2.circle.fill")
                    Label("Toggle it ON", systemImage: "3.circle.fill")
                }
                .font(.body)

                Divider()

                Text("If permission doesn't work after an update:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Remove DockAnchor from the list (- button)", systemImage: "1.circle")
                    Label("Re-add it (+ button)", systemImage: "2.circle")
                    Label("Toggle it ON", systemImage: "3.circle")
                }
                .font(.body)
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    dockMonitor.openAccessibilityPreferences()
                }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Open Accessibility Settings")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 380, height: 420)
        .background(.background)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
        .environmentObject(DockMonitor())
        .environmentObject(UpdateChecker())
}

