//
//  ProfilesSection.swift
//  DockAnchor
//

import SwiftUI

struct ProfilesSection: View {
    @EnvironmentObject var appSettings: AppSettings
    @Binding var showingNewProfile: Bool
    @Binding var editingProfile: DockProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Profiles").font(.headline)
                Spacer()
                Button(action: { showingNewProfile = true }) {
                    Image(systemName: "plus.circle").font(.system(size: 16))
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
    }
}
