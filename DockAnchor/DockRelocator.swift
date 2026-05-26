//
//  DockRelocator.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics

extension DockMonitor {

    func detectCurrentDockPosition() {
        dockPosition = .bottom
    }

    private func getCurrentDockPosition() -> DockPosition {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.dock", "orientation"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let orientation = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            switch orientation {
            case "left":  return .left
            case "right": return .right
            default:      return .bottom
            }
        } catch {
            return .bottom
        }
    }

    private func getDisplayForDockPosition(_ position: DockPosition) -> CGDirectDisplayID {
        if position == .bottom {
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: {
                let f = $0.frame
                return mouseLocation.x >= f.minX && mouseLocation.x <= f.maxX &&
                       mouseLocation.y >= f.minY && mouseLocation.y <= f.maxY
            }) {
                return CGDirectDisplayID(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0)
            }
        }
        return CGMainDisplayID()
    }

    func relocateDockToAnchoredDisplay() {
        guard let anchorDisplay = availableDisplays.first(where: { $0.id == anchorDisplayID }) else {
            statusMessage = "Cannot relocate dock - anchor display not found"
            return
        }

        if isDockOnAnchoredDisplay() {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Dock is already on \(anchorDisplay.name)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                }
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Relocating dock to \(anchorDisplay.name)..."
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let originalPosition = CGEvent(source: nil)?.location ?? .zero

            var temporaryTapCreated = false
            if self.eventTap == nil {
                temporaryTapCreated = self.createEventTapForRelocation()
            }

            self.isRelocating = true

            DispatchQueue.main.sync { NSCursor.hide() }

            let eventSource = CGEventSource(stateID: .hidSystemState)
            let approachPoint = self.getApproachPoint(for: anchorDisplay)
            let edgePoint = self.getDockTriggerPoint(for: anchorDisplay)

            CGWarpMouseCursorPosition(approachPoint)
            Thread.sleep(forTimeInterval: 0.03)

            for i in 0..<8 {
                let progress = CGFloat(i) / 7.0
                let current = CGPoint(
                    x: approachPoint.x + (edgePoint.x - approachPoint.x) * progress,
                    y: approachPoint.y + (edgePoint.y - approachPoint.y) * progress
                )
                CGWarpMouseCursorPosition(current)
                if let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left) {
                    e.setIntegerValueField(.eventSourceUserData, value: self.syntheticEventMarker)
                    e.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: 0.015)
            }

            for _ in 0..<8 {
                CGWarpMouseCursorPosition(edgePoint)
                if let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: edgePoint, mouseButton: .left) {
                    e.setIntegerValueField(.eventSourceUserData, value: self.syntheticEventMarker)
                    e.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: 0.025)
            }

            CGWarpMouseCursorPosition(originalPosition)
            self.isRelocating = false

            if temporaryTapCreated { self.removeTemporaryEventTap() }

            DispatchQueue.main.sync { NSCursor.unhide() }

            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Dock relocated to \(anchorDisplay.name)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                }
            }
        }
    }

    func isDockOnAnchoredDisplay() -> Bool {
        guard availableDisplays.count > 1 else { return true }
        guard let currentDockDisplay = getCurrentDockDisplayID() else { return false }
        return currentDockDisplay == anchorDisplayID
    }

    private func getCurrentDockDisplayID() -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else { continue }
            let f = screen.frame
            let vf = screen.visibleFrame
            switch dockPosition {
            case .bottom where vf.minY > f.minY: return displayID
            case .left   where vf.minX > f.minX: return displayID
            case .right  where vf.maxX < f.maxX: return displayID
            default: continue
            }
        }

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else { return nil }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windows[0], kAXPositionAttribute as CFString, &positionValue) == .success else { return nil }

        var position = CGPoint.zero
        guard let pv = positionValue, AXValueGetValue(pv as! AXValue, .cgPoint, &position) else { return nil }
        return availableDisplays.first { $0.frame.contains(position) }?.id
    }

    private func getApproachPoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        let offset: CGFloat = 50
        switch dockPosition {
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY - offset)
        case .left:   return CGPoint(x: frame.minX + offset, y: frame.midY)
        case .right:  return CGPoint(x: frame.maxX - offset, y: frame.midY)
        }
    }

    private func getPastEdgePoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        let overshoot: CGFloat = 20
        switch dockPosition {
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY + overshoot)
        case .left:   return CGPoint(x: frame.minX - overshoot, y: frame.midY)
        case .right:  return CGPoint(x: frame.maxX + overshoot, y: frame.midY)
        }
    }

    private func getDockTriggerPoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        switch dockPosition {
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY - 1)
        case .left:   return CGPoint(x: frame.minX + 1, y: frame.midY)
        case .right:  return CGPoint(x: frame.maxX - 1, y: frame.midY)
        }
    }
}
