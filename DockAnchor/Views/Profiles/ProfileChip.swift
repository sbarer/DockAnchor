//
//  ProfileChip.swift
//  DockAnchor
//

import SwiftUI

struct ProfileChip: View {
    let profile: DockProfile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if profile.autoActivate {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(isActive ? .white.opacity(0.8) : .orange)
            }

            Text(profile.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .primary)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .white.opacity(0.8) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thickMaterial)
            }
        }
        .overlay {
            if !isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onEdit() }
        .onHover { hovering in isHovering = hovering }
    }
}
