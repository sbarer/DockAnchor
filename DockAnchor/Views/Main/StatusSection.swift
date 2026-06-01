//
//  StatusSection.swift
//  DockAnchor
//

import SwiftUI

struct StatusSection: View {
    @EnvironmentObject var coordinator: DockCoordinator
    @Binding var showingPermissionHelp: Bool

    private var statusColor: Color {
        if coordinator.statusMessage.contains("Blocked") { return .red }
        if coordinator.isActive { return .green }
        return .primary
    }

    var body: some View {
        VStack(spacing: 12) {
            statusRow
            if coordinator.needsPermissionReset || coordinator.statusMessage.lowercased().contains("permission") {
                permissionWarningRow
            } else if !coordinator.isActive {
                inactiveWarningRow
            }
        }
        .cardStyle()
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            if coordinator.statusMessage.contains("Blocked") {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            } else {
                Circle()
                    .fill(coordinator.isActive ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }
            Text(coordinator.statusMessage)
                .font(.headline)
                .foregroundColor(statusColor)
            Spacer()
        }
    }

    @ViewBuilder private var permissionWarningRow: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Accessibility permission required")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Help") { showingPermissionHelp = true }
                .font(.caption)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var inactiveWarningRow: some View {
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
