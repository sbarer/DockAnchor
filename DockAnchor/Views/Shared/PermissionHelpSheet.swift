//
//  PermissionHelpSheet.swift
//  DockAnchor
//

import SwiftUI

struct PermissionHelpSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            headerRow
            VStack(alignment: .leading, spacing: 16) {
                Text("Dock Anchor Deluxe requires Accessibility permission to monitor mouse movement and keep your dock anchored.")
                    .font(.body)
                Divider()
                enableInstructions
                Divider()
                resetInstructions
                Spacer()
                openSettingsButton
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 380, height: 420)
        .background(.background)
    }

    @ViewBuilder private var headerRow: some View {
        HStack {
            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    @ViewBuilder private var enableInstructions: some View {
        Text("How to enable:")
            .font(.headline)
        VStack(alignment: .leading, spacing: 8) {
            Label("Click \"Open Accessibility Settings\" below", systemImage: "1.circle.fill")
            Label("Find Dock Anchor Deluxe in the list", systemImage: "2.circle.fill")
            Label("Toggle it ON", systemImage: "3.circle.fill")
        }
        .font(.body)
    }

    @ViewBuilder private var resetInstructions: some View {
        Text("If permission doesn't work after an update:")
            .font(.headline)
        VStack(alignment: .leading, spacing: 8) {
            Label("Remove Dock Anchor Deluxe from the list (- button)", systemImage: "1.circle")
            Label("Re-add it (+ button)", systemImage: "2.circle")
            Label("Toggle it ON", systemImage: "3.circle")
        }
        .font(.body)
        .foregroundColor(.secondary)
    }

    @ViewBuilder private var openSettingsButton: some View {
        Button(action: { PermissionService.shared.openPreferences() }) {
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
}
