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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dockHeader
            if appSettings.activeProfile != nil { autoActivateRow }
            positionRow
            sizeRow
            if dockChangesPending { pendingActionsRow }
        }
        .cardStyle()
        .onAppear { initDockState() }
        .onChange(of: appSettings.activeProfileID) { _, _ in initDockState() }
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

    @ViewBuilder private var autoActivateRow: some View {
        if let profile = appSettings.activeProfile {
            HStack {
                Text("Auto-activate when display connects").font(.callout)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.autoActivate },
                    set: { newValue in
                        var updated = profile
                        updated.autoActivate = newValue
                        appSettings.updateProfile(updated)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder private var positionRow: some View {
        HStack {
            Text("Position").font(.callout)
            Spacer()
            Picker("", selection: Binding(
                get: { liveDockPosition },
                set: { newValue in
                    liveDockPosition = newValue
                    dockChangesPending = true
                    coordinator.applyDockSettings(position: newValue, tileSize: nil)
                }
            )) {
                ForEach(DockPosition.allCases, id: \.self) { pos in
                    Text(pos.label).tag(pos)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
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
