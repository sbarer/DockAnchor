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
        print("[DockAnchor] Starting relocateDockToAnchoredDisplay")
        guard let anchorDisplay = availableDisplays.first(where: { $0.id == anchorDisplayID }) else {
            statusMessage = "Cannot relocate dock - anchor display not found"
            return
        }

        if isDockOnAnchoredDisplay() {
            DispatchQueue.main.async { [weak self] in
                print("[DockAnchor:relocateDockToAnchoredDisplay] isDockOnAnchoredDisplay==true, starting timer to check again")
                self?.statusMessage = "Dock is already on \(anchorDisplay.name)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self else { return }
                    self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                    print("[DockAnchor:relocateDockToAnchoredDisplay] in 1 second check loop")
                }
            }
            return
        }

        guard !isRelocating else {
            print("[DockAnchor] relocate: skipped — already relocating")
            return
        }

        // Capture position on main thread before dispatch; CGEvent(source:nil) always returns (0,0)
        let nsMousePos = NSEvent.mouseLocation
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0
        let originalPosition = CGPoint(x: nsMousePos.x, y: mainScreenHeight - nsMousePos.y)

        print("[DockAnchor] relocate: starting — originalPos=\(originalPosition) anchorID=\(anchorDisplayID)")
        isRelocating = true

        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Relocating dock to \(anchorDisplay.name)..."
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var temporaryTapCreated = false
            if self.eventTap == nil {
                temporaryTapCreated = self.createEventTapForRelocation()
            }

            DispatchQueue.main.sync { NSCursor.hide() }

            let eventSource = CGEventSource(stateID: .hidSystemState)
            let approachPoint = self.getPastEdgePoint(for: anchorDisplay)
            let edgePoint = self.getDockTriggerPoint(for: anchorDisplay)

            print("[DockAnchor] relocate: cross-boundary sweep from \(approachPoint) to \(edgePoint)")

            CGWarpMouseCursorPosition(approachPoint)
            Thread.sleep(forTimeInterval: 0.03)

            // Animate toward edge — no synthetic marker so Dock sees these as real hover events
            for i in 0..<8 {
                let progress = CGFloat(i) / 7.0
                let current = CGPoint(
                    x: approachPoint.x + (edgePoint.x - approachPoint.x) * progress,
                    y: approachPoint.y + (edgePoint.y - approachPoint.y) * progress
                )
                CGWarpMouseCursorPosition(current)
                if let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left) {
                    e.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: 0.015)
            }

            // Pin cursor to edge so physical mouse movement can't drift it away during dwell
            CGAssociateMouseAndMouseCursorPosition(0)
            CGWarpMouseCursorPosition(edgePoint)

            // Dwell for ~1000ms — macOS dock hover detection requires ~500ms sustained presence
            for _ in 0..<20 {
                if let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: edgePoint, mouseButton: .left) {
                    e.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: 0.050)
            }

            CGAssociateMouseAndMouseCursorPosition(1)
            let safePosition = self.clampedToScreenEdge(originalPosition)
            CGWarpMouseCursorPosition(safePosition)
            let mainH = NSScreen.main?.frame.height ?? 0
            let destName = self.availableDisplays.first(where: {
                CGRect(x: $0.frame.minX, y: mainH - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height).contains(safePosition)
            })?.name ?? "unknown"
            print("[DockAnchor] relocate: complete — restoring cursor to \(safePosition) (original: \(originalPosition)) on screen \(destName)")
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
        guard let currentDockDisplay = getCurrentDockDisplayID() else {
            print("[DockAnchor] isDockOnAnchor: getCurrentDockDisplayID returned nil")
            return false
        }
        let result = currentDockDisplay == anchorDisplayID
        print("[DockAnchor] isDockOnAnchor: currentDockID=\(currentDockDisplay) anchorID=\(anchorDisplayID) match=\(result)")
        return result
    }

    private func getCurrentDockDisplayID() -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else { continue }
            let f = screen.frame
            let vf = screen.visibleFrame
            print("[DockAnchor] getCurrentDockDisplayID: screen=\(displayID) frame=\(f) visibleFrame=\(vf) dockPos=\(dockPosition)")
            switch dockPosition {
            case .bottom where vf.minY > f.minY:
                print("[DockAnchor] getCurrentDockDisplayID: found dock on \(displayID) via visibleFrame (bottom)")
                return displayID
            case .left   where vf.minX > f.minX:
                print("[DockAnchor] getCurrentDockDisplayID: found dock on \(displayID) via visibleFrame (left)")
                return displayID
            case .right  where vf.maxX < f.maxX:
                print("[DockAnchor] getCurrentDockDisplayID: found dock on \(displayID) via visibleFrame (right)")
                return displayID
            default: continue
            }
        }

        print("[DockAnchor] getCurrentDockDisplayID: visibleFrame method failed, falling back to AX")
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            print("[DockAnchor] getCurrentDockDisplayID: dock app not found")
            return nil
        }
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("[DockAnchor] getCurrentDockDisplayID: AX windows query failed")
            return nil
        }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windows[0], kAXPositionAttribute as CFString, &positionValue) == .success else {
            print("[DockAnchor] getCurrentDockDisplayID: AX position query failed")
            return nil
        }

        var position = CGPoint.zero
        guard let pv = positionValue, AXValueGetValue(pv as! AXValue, .cgPoint, &position) else { return nil }
        let found = availableDisplays.first { $0.frame.contains(position) }?.id
        print("[DockAnchor] getCurrentDockDisplayID: AX dock position=\(position) found on displayID=\(String(describing: found))")
        return found
    }

    private func getApproachPoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        let safe = getSafeEdgeOffset(for: display)
        let offset: CGFloat = 50
        switch dockPosition {
        case .bottom: return CGPoint(x: safe, y: frame.maxY - offset)
        case .left:   return CGPoint(x: frame.minX + offset, y: safe)
        case .right:  return CGPoint(x: frame.maxX - offset, y: safe)
        }
    }

    private func getPastEdgePoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        let safe = getSafeEdgeOffset(for: display)
        let overshoot: CGFloat = 20
        switch dockPosition {
        case .bottom: return CGPoint(x: safe, y: frame.maxY + overshoot)
        case .left:   return CGPoint(x: frame.minX - overshoot, y: safe)
        case .right:  return CGPoint(x: frame.maxX + overshoot, y: safe)
        }
    }

    private func getDockTriggerPoint(for display: DisplayInfo) -> CGPoint {
        let frame = display.frame
        let safe = getSafeEdgeOffset(for: display)
        switch dockPosition {
        case .bottom: return CGPoint(x: safe, y: frame.maxY - 1)
        case .left:   return CGPoint(x: frame.minX + 1, y: safe)
        case .right:  return CGPoint(x: frame.maxX - 1, y: safe)
        }
    }

    // Returns the midpoint of the largest segment of the dock edge not shared with any other display.
    private func getSafeEdgeOffset(for display: DisplayInfo) -> CGFloat {
        let frame = display.frame
        let (rangeMin, rangeMax): (CGFloat, CGFloat)
        var covered: [(CGFloat, CGFloat)] = []
        let t: CGFloat = 2

        switch dockPosition {
        case .bottom:
            rangeMin = frame.minX; rangeMax = frame.maxX
            for other in availableDisplays where other.id != display.id {
                guard abs(other.frame.minY - frame.maxY) < t || abs(other.frame.maxY - frame.maxY) < t else { continue }
                let lo = max(frame.minX, other.frame.minX), hi = min(frame.maxX, other.frame.maxX)
                if hi > lo { covered.append((lo, hi)) }
            }
        case .left:
            rangeMin = frame.minY; rangeMax = frame.maxY
            for other in availableDisplays where other.id != display.id {
                guard abs(other.frame.maxX - frame.minX) < t else { continue }
                let lo = max(frame.minY, other.frame.minY), hi = min(frame.maxY, other.frame.maxY)
                if hi > lo { covered.append((lo, hi)) }
            }
        case .right:
            rangeMin = frame.minY; rangeMax = frame.maxY
            for other in availableDisplays where other.id != display.id {
                guard abs(other.frame.minX - frame.maxX) < t else { continue }
                let lo = max(frame.minY, other.frame.minY), hi = min(frame.maxY, other.frame.maxY)
                if hi > lo { covered.append((lo, hi)) }
            }
        }

        let free = subtractRanges(from: (rangeMin, rangeMax), subtract: covered)
        let best = free.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }) ?? (rangeMin, rangeMax)
        print("[DockAnchor] getSafeEdgeOffset: range=\(rangeMin)..\(rangeMax) covered=\(covered) best=\(best)")
        return (best.0 + best.1) / 2
    }

    private func clampedToScreenEdge(_ point: CGPoint, buffer: CGFloat = 15) -> CGPoint {
        let mainH = NSScreen.main?.frame.height ?? 0
        for display in availableDisplays {
            let f = display.frame
            let cgBounds = CGRect(x: f.minX, y: mainH - f.maxY, width: f.width, height: f.height)
            guard cgBounds.contains(point) else { continue }
            return CGPoint(
                x: max(f.minX + buffer, min(f.maxX - buffer, point.x)),
                y: max(cgBounds.minY + buffer, min(cgBounds.maxY - buffer, point.y))
            )
        }
        return point
    }

    private func subtractRanges(from range: (CGFloat, CGFloat), subtract: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
        var free = [range]
        for cov in subtract {
            free = free.flatMap { seg -> [(CGFloat, CGFloat)] in
                let (a, b) = seg
                let c = max(cov.0, a), d = min(cov.1, b)
                if d <= c { return [(a, b)] }
                var result: [(CGFloat, CGFloat)] = []
                if c > a { result.append((a, c)) }
                if d < b { result.append((d, b)) }
                return result
            }
        }
        return free
    }

    /// Applies dock position and/or size via System Events's dock preferences API.
    /// No Dock restart required — System Events updates the Dock in-place with no side effects.
    func applyDockSettings(position: DockPosition?, tileSize: Int?) {
        guard position != nil || tileSize != nil else {
            print("[DockSettings] applyDockSettings: skipped — both args nil")
            return
        }

        print("[DockSettings] applyDockSettings: position=\(position?.rawValue ?? "unchanged"), tileSize=\(tileSize.map(String.init) ?? "unchanged")")

        var scriptLines = ["tell application \"System Events\" to tell dock preferences"]
        if let position = position {
            scriptLines.append("    set screen edge to \(position.rawValue)")
        }
        if let size = tileSize {
            scriptLines.append("    set dock size to \(size)")
        }
        scriptLines.append("end tell")
        let source = scriptLines.joined(separator: "\n")
        print("[DockSettings] AppleScript:\n\(source)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // System Events must be running to receive Apple Events
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty {
                print("[DockSettings] System Events not running — launching")
                DispatchQueue.main.sync {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"))
                }
                var waited = 0.0
                while NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty && waited < 5.0 {
                    Thread.sleep(forTimeInterval: 0.2)
                    waited += 0.2
                }
                Thread.sleep(forTimeInterval: 0.5) // extra buffer for AE server init
                print("[DockSettings] System Events ready after \(String(format: "%.1f", waited + 0.5))s")
            }

            DispatchQueue.main.async { [weak self] in
                let script = NSAppleScript(source: source)
                var errorInfo: NSDictionary?
                script?.executeAndReturnError(&errorInfo)
                if let errorInfo = errorInfo {
                    print("[DockSettings] NSAppleScript error: \(errorInfo)")
                } else {
                    print("[DockSettings] NSAppleScript applied successfully")
                }
                if let position = position {
                    self?.dockPosition = position
                    print("[DockSettings] DockMonitor.dockPosition updated to \(position.rawValue)")
                }
            }
        }
    }

    /// Reads the current dock orientation via `defaults read`. Blocks the calling thread briefly.
    static func readCurrentDockPosition() -> DockPosition {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.dock", "orientation"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return DockPosition(rawValue: str) ?? .bottom
        } catch {
            return .bottom
        }
    }

    /// Reads the current dock tile size via `defaults read`. Blocks the calling thread briefly.
    static func readCurrentDockTileSize() -> Int {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.dock", "tilesize"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Int(str) ?? 48
        } catch {
            return 48
        }
    }
}
