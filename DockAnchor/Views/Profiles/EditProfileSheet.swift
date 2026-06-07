//
//  EditProfileSheet.swift
//  DockAnchor
//

import SwiftUI

struct EditProfileSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) var dismiss
    let profile: DockProfile
    @State private var profileName: String
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    init(profile: DockProfile) {
        self.profile = profile
        _profileName = State(initialValue: profile.name)
    }

    private var isActive: Bool { appSettings.activeProfileID == profile.id }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Profile").font(.headline)

            TextField("Profile Name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            Divider()

            activateButton

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
                Button("Save") { saveProfile(); dismiss() }
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
            Button("Delete", role: .destructive) { appSettings.deleteProfile(profile); dismiss() }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder private var activateButton: some View {
        Button(action: {
            if isActive { appSettings.deactivateProfile(); dismiss() }
            else { activateWithCurrentEdits() }
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
    }

    private func saveProfile() {
        var updated = profile
        updated.name = profileName
        appSettings.updateProfile(updated)
    }

    private func activateWithCurrentEdits() {
        var updated = profile
        updated.name = profileName
        appSettings.updateProfile(updated)
        appSettings.switchToProfile(updated)
        dismiss()
    }
}
