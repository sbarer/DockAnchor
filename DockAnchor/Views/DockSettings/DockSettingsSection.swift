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
    @State private var showingHotCorners = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dockHeader
            if appSettings.activeProfile != nil { autoActivateRow }
            positionRow
            sizeRow
            hotCornersRow
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
                    coordinator.applyDockSettings(position: newValue, tileSize: nil)
                    saveToActiveProfileIfNeeded()
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
                coordinator.applyDockSettings(position: nil, tileSize: Int(liveDockTileSize))
                saveToActiveProfileIfNeeded()
            }
        }
    }

    @ViewBuilder private var hotCornersRow: some View {
        HStack {
            Text("Hot Corners").font(.callout)
            Spacer()
            Button("Customize") { showingHotCorners = true }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingHotCorners, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hot Corners").font(.headline)
                        Text("Corner areas are excluded from edge blocking so macOS hot corners still fire.")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(coordinator.displays) { display in
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
                    .padding()
                    .frame(minWidth: 280)
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
    }

    private func saveToActiveProfileIfNeeded() {
        guard var profile = appSettings.activeProfile else { return }
        profile.dockPosition = liveDockPosition
        profile.dockTileSize = Int(liveDockTileSize)
        appSettings.updateProfile(profile)
    }
}
