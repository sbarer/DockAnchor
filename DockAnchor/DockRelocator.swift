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

    func changeDockPosition(to position: DockPosition) {
        let source = "tell application \"System Events\" to tell dock preferences\n    set screen edge to \(position.rawValue)\nend tell"
        print("[DockSettings] changeDockPosition: \(position.rawValue)")

        DispatchQueue.main.async { [weak self] in
            let script = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            script?.executeAndReturnError(&errorInfo)
            if let errorInfo = errorInfo {
                print("[DockSettings] changeDockPosition error: \(errorInfo)")
            } else {
                self?.dockPosition = position
                print("[DockSettings] changeDockPosition applied: \(position.rawValue)")
            }
        }

        relocateDockToAnchoredDisplay()
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
}
