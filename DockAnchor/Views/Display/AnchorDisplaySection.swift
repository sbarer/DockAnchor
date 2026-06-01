//
//  AnchorDisplaySection.swift
//  DockAnchor
//

import SwiftUI

struct AnchorDisplaySection: View {
    @EnvironmentObject var coordinator: DockCoordinator
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anchor Display")
                .font(.headline)

            DisplayArrangementView(
                displays: coordinator.displays,
                selectedDisplayUUID: $appSettings.selectedDisplayUUID,
                maxHeight: 100
            )
            .padding(.vertical, 4)

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("Anchored to: \(coordinator.anchoredDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text("Click a display to anchor the dock there")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .cardStyle()
    }
}
