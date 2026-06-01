//
//  DisplayArrangementView.swift
//  DockAnchor
//

import SwiftUI

struct DisplayArrangementView: View {
    let displays: [DisplayInfo]
    @Binding var selectedDisplayUUID: String
    var maxHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            let layout = calculateLayout(containerSize: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let frame = layout.scaledFrames[display.id] ?? .zero
                    DisplayRectangleView(
                        display: display,
                        isSelected: display.uuid == selectedDisplayUUID,
                        size: CGSize(width: frame.width, height: frame.height)
                    )
                    .offset(x: frame.minX, y: frame.minY)
                    .onTapGesture { selectedDisplayUUID = display.uuid }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(height: maxHeight)
    }

    private func calculateLayout(containerSize: CGSize) -> DisplayLayout {
        guard !displays.isEmpty else { return DisplayLayout(scaledFrames: [:], scale: 1.0) }

        let minX = displays.map { $0.frame.minX }.min() ?? 0
        let minY = displays.map { $0.frame.minY }.min() ?? 0
        let maxX = displays.map { $0.frame.maxX }.max() ?? 0
        let maxY = displays.map { $0.frame.maxY }.max() ?? 0

        let totalWidth = maxX - minX
        let totalHeight = maxY - minY
        guard totalWidth > 0 && totalHeight > 0 else { return DisplayLayout(scaledFrames: [:], scale: 1.0) }

        let padding: CGFloat = 10
        let availableWidth = containerSize.width - padding * 2
        let availableHeight = containerSize.height - padding * 2
        let scale = min(availableWidth / totalWidth, availableHeight / totalHeight)

        let scaledTotalWidth = totalWidth * scale
        let scaledTotalHeight = totalHeight * scale
        let offsetX = (containerSize.width - scaledTotalWidth) / 2
        let offsetY = (containerSize.height - scaledTotalHeight) / 2

        var scaledFrames: [CGDirectDisplayID: CGRect] = [:]
        for display in displays {
            let x = (display.frame.minX - minX) * scale + offsetX
            let y = (display.frame.minY - minY) * scale + offsetY
            scaledFrames[display.id] = CGRect(x: x, y: y, width: display.frame.width * scale, height: display.frame.height * scale)
        }

        return DisplayLayout(scaledFrames: scaledFrames, scale: scale)
    }

    struct DisplayLayout {
        let scaledFrames: [CGDirectDisplayID: CGRect]
        let scale: CGFloat
    }
}
