//
//  NewProfileSheet.swift
//  DockAnchor
//

import SwiftUI

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
                Button("Cancel") { dismiss() }
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
