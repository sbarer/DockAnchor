//
//  DisplayRectangleView.swift
//  DockAnchor
//

import SwiftUI

struct DisplayRectangleView: View {
    @Environment(\.colorScheme) var colorScheme
    let display: DisplayInfo
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.5) : Color.primary.opacity(0.2)),
                    lineWidth: isSelected ? 2 : 1
                )

            VStack(spacing: 1) {
                Text(displayLabel)
                    .font(.system(size: fontSize))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : (colorScheme == .dark ? .white : .secondary))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)

                if display.isPrimary {
                    Text("(Primary)")
                        .font(.system(size: max(fontSize - 2, 7)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(4)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private var displayLabel: String {
        display.name
            .replacingOccurrences(of: " (Primary)", with: "")
            .replacingOccurrences(of: "Built-in ", with: "")
            .replacingOccurrences(of: " Display", with: "")
    }

    private var fontSize: CGFloat {
        let minDimension = min(size.width, size.height)
        if minDimension < 40 { return 8 }
        if minDimension < 60 { return 9 }
        return 10
    }
}
