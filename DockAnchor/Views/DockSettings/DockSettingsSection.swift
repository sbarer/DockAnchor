//
//  DockSettingsSection.swift
//  DockAnchor
//

import SwiftUI

struct DockSettingsSection: View {
    @EnvironmentObject var coordinator: DockCoordinator
    @EnvironmentObject var appSettings: AppSettings
    @State private var liveDockPosition: DockPosition = .bottom
    @State private var liveDockTileSize: Double = 48
    @State private var originalDockPosition: DockPosition = .bottom
    @State private var originalDockTileSize: Double = 48
    @State private var dockChangesPending = false
    @State private var hoveredBlockedPosition: DockPosition? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dockHeader
            positionRow
            sizeRow
            if dockChangesPending { pendingActionsRow }
        }
        .cardStyle()
        .onAppear { initDockState() }
        .onChange(of: appSettings.activeProfileID) { _, _ in initDockState() }
        .onChange(of: appSettings.selectedDisplayUUID) { _, _ in
            initDockState()
            validateAndFixPosition()
        }
    }

    @ViewBuilder private var dockHeader: some View {
        HStack {
            Text("Dock").font(.headline)
            if let profile = appSettings.activeProfile {
                Text("· \(profile.name)").font(.callout).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var positionRow: some View {
        HStack {
            Text("Position").font(.callout)
            Spacer()
            HStack(spacing: 4) {
                ForEach(DockPosition.allCases, id: \.self) { pos in
                    positionButton(for: pos)
                }
            }
        }
    }

    @ViewBuilder private func positionButton(for pos: DockPosition) -> some View {
        let blocked = isEdgeBlocked(pos)
        let isSelected = liveDockPosition == pos

        Button(action: {
            guard !blocked else { return }
            liveDockPosition = pos
            dockChangesPending = true
            coordinator.applyDockSettings(position: pos, tileSize: nil)
        }) {
            Text(pos.label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
                .opacity(blocked ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && blocked {
                hoveredBlockedPosition = pos
            } else if hoveredBlockedPosition == pos {
                hoveredBlockedPosition = nil
            }
        }
        .popover(isPresented: Binding(
            get: { hoveredBlockedPosition == pos },
            set: { if !$0 { hoveredBlockedPosition = nil } }
        )) {
            Text("The OS doesn't allow the dock here — this edge is fully shared with another display.")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: 220)
        }
    }

    private func isEdgeBlocked(_ position: DockPosition) -> Bool {
        let displays = coordinator.displays
        guard let anchor = displays.first(where: { $0.uuid == appSettings.selectedDisplayUUID }) else { return false }
        return anchor.isEdgeBlocked(position, in: displays)
    }

    private func validateAndFixPosition() {
        let displays = coordinator.displays
        guard let anchor = displays.first(where: { $0.uuid == appSettings.selectedDisplayUUID }) else { return }
        guard anchor.isEdgeBlocked(liveDockPosition, in: displays) else { return }
        guard let valid = [DockPosition.bottom, .left, .right].first(where: { !anchor.isEdgeBlocked($0, in: displays) }) else { return }
        liveDockPosition = valid
        dockChangesPending = true
        coordinator.applyDockSettings(position: valid, tileSize: nil)
    }

    @ViewBuilder private var sizeRow: some View {
        HStack {
            Text("Size").font(.callout)
            Spacer()
            Text("\(Int(liveDockTileSize))%")
                .font(.callout)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        Slider(value: $liveDockTileSize, in: 5...55, step: 5) { editing in
            if !editing {
                dockChangesPending = true
                coordinator.applyDockSettings(position: nil, tileSize: Int(liveDockTileSize))
            }
        }
    }

    @ViewBuilder private var pendingActionsRow: some View {
        HStack {
            Button("Revert") {
                liveDockPosition = originalDockPosition
                liveDockTileSize = originalDockTileSize
                coordinator.applyDockSettings(position: originalDockPosition, tileSize: Int(originalDockTileSize))
                dockChangesPending = false
            }
            .buttonStyle(.bordered)
            Spacer()
            if appSettings.activeProfile != nil {
                Button("Save to Profile") { saveDockSettingsToActiveProfile() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func initDockState() {
        let systemPosition = DockResizeService.shared.currentPosition()
        let systemSize = Double(DockResizeService.shared.currentTileSize())
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
