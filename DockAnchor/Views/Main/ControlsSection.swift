//
//  ControlsSection.swift
//  DockAnchor
//

import SwiftUI

struct ControlsSection: View {
    @EnvironmentObject var coordinator: DockCoordinator
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 16) {
            protectionButton
            settingsButton
        }
    }

    @ViewBuilder private var protectionButton: some View {
        Button(action: {
            if coordinator.isActive { coordinator.stopMonitoring() }
            else { coordinator.startMonitoring() }
        }) {
            HStack {
                Image(systemName: coordinator.isActive ? "stop.circle" : "play.circle")
                Text(coordinator.isActive ? "Stop Protection" : "Start Protection")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(coordinator.isActive ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder private var settingsButton: some View {
        Button(action: { showingSettings = true }) {
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
}
