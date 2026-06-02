//
//  DockRelocationService.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics

class DockRelocationService {
    static let shared = DockRelocationService()

    private(set) var isRelocating: Bool = false

    // Set by DockCoordinator (Phase 3)
    var onStatusMessage: ((String) -> Void)?

    private init() {}

    // MARK: - Public API

    func relocate(to display: DisplayInfo, dockPosition: DockPosition) async {
        guard !isDockOnDisplay(display, dockPosition: dockPosition) else {
            onStatusMessage?("Dock is already on \(display.name)")
            return
        }

        guard !isRelocating else {
            print("[DockRelocationService] relocate: skipped — already relocating")
            return
        }

        let originalPosition = await MainActor.run {
            let nsMousePos = NSEvent.mouseLocation
            let mainScreenHeight = NSScreen.main?.frame.height ?? 0
            return CGPoint(x: nsMousePos.x, y: mainScreenHeight - nsMousePos.y)
        }

        print("[DockRelocationService] relocate: starting — originalPos=\(originalPosition) displayID=\(display.id)")
        isRelocating = true
        onStatusMessage?("Relocating dock to \(display.name)...")

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { continuation.resume(); return }

                self.prepareEventTap()

                DispatchQueue.main.sync { NSCursor.hide() }

                let source = CGEventSource(stateID: .hidSystemState)
                let approachPoint = self.pastEdgePoint(for: display, dockPosition: dockPosition)
                let edgePoint = self.triggerPoint(for: display, dockPosition: dockPosition)

                print("[DockRelocationService] relocate: sweep \(approachPoint) → \(edgePoint)")

                self.sweepCursor(from: approachPoint, to: edgePoint, source: source)
                self.dwellAtEdge(edgePoint, source: source)
                self.restoreCursor(to: originalPosition)

                self.isRelocating = false
                self.removeTemporaryTap()

                DispatchQueue.main.sync { NSCursor.unhide() }

                DispatchQueue.main.async { [weak self] in
                    self?.onStatusMessage?("Dock relocated to \(display.name)")
                }

                continuation.resume()
            }
        }
    }

    func isDockOnDisplay(_ display: DisplayInfo, dockPosition: DockPosition) -> Bool {
        let displays = DisplayService.shared.displays
        guard displays.count > 1 else { return true }
        guard let currentID = currentDockDisplayID(dockPosition: dockPosition) else {
            print("[DockRelocationService] isDockOnDisplay: currentDockDisplayID returned nil")
            return false
        }
        let result = currentID == display.id
        print("[DockRelocationService] isDockOnDisplay: currentID=\(currentID) displayID=\(display.id) match=\(result)")
        return result
    }

    // MARK: - Internal (testable) geometry helpers

    func subtractRanges(
        from range: (CGFloat, CGFloat),
        subtract: [(CGFloat, CGFloat)]
    ) -> [(CGFloat, CGFloat)] {
        var free = [range]
        for cov in subtract {
            free = free.flatMap { seg -> [(CGFloat, CGFloat)] in
                let (a, b) = seg
                let c = max(cov.0, a)
                let d = min(cov.1, b)
                if d <= c { return [(a, b)] }
                var result: [(CGFloat, CGFloat)] = []
                if c > a { result.append((a, c)) }
                if d < b { result.append((d, b)) }
                return result
            }
        }
        return free
    }

    func safeEdgeOffset(for display: DisplayInfo, dockPosition: DockPosition) -> CGFloat {
        let displays = DisplayService.shared.displays
        let frame = display.frame
        let (rangeMin, rangeMax): (CGFloat, CGFloat)
        var covered: [(CGFloat, CGFloat)] = []
        let t: CGFloat = 2

        switch dockPosition {
        case .bottom:
            rangeMin = frame.minX; rangeMax = frame.maxX
            for other in displays where other.id != display.id {
                guard abs(other.frame.minY - frame.maxY) < t || abs(other.frame.maxY - frame.maxY) < t else { continue }
                let lo = max(frame.minX, other.frame.minX)
                let hi = min(frame.maxX, other.frame.maxX)
                if hi > lo { covered.append((lo, hi)) }
            }
        case .left:
            rangeMin = frame.minY; rangeMax = frame.maxY
            for other in displays where other.id != display.id {
                guard abs(other.frame.maxX - frame.minX) < t else { continue }
                let lo = max(frame.minY, other.frame.minY)
                let hi = min(frame.maxY, other.frame.maxY)
                if hi > lo { covered.append((lo, hi)) }
            }
        case .right:
            rangeMin = frame.minY; rangeMax = frame.maxY
            for other in displays where other.id != display.id {
                guard abs(other.frame.minX - frame.maxX) < t else { continue }
                let lo = max(frame.minY, other.frame.minY)
                let hi = min(frame.maxY, other.frame.maxY)
                if hi > lo { covered.append((lo, hi)) }
            }
        }

        let free = subtractRanges(from: (rangeMin, rangeMax), subtract: covered)
        let best = free.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }) ?? (rangeMin, rangeMax)
        print("[DockRelocationService] safeEdgeOffset: range=\(rangeMin)..\(rangeMax) covered=\(covered) best=\(best)")
        return (best.0 + best.1) / 2
    }

    func triggerPoint(for display: DisplayInfo, dockPosition: DockPosition) -> CGPoint {
        let frame = display.frame
        let safe = safeEdgeOffset(for: display, dockPosition: dockPosition)
        switch dockPosition {
        case .bottom: return CGPoint(x: safe, y: frame.maxY - 1)
        case .left:   return CGPoint(x: frame.minX + 1, y: safe)
        case .right:  return CGPoint(x: frame.maxX - 1, y: safe)
        }
    }

    func pastEdgePoint(for display: DisplayInfo, dockPosition: DockPosition) -> CGPoint {
        let frame = display.frame
        let safe = safeEdgeOffset(for: display, dockPosition: dockPosition)
        let overshoot: CGFloat = 20
        switch dockPosition {
        case .bottom: return CGPoint(x: safe, y: frame.maxY + overshoot)
        case .left:   return CGPoint(x: frame.minX - overshoot, y: safe)
        case .right:  return CGPoint(x: frame.maxX + overshoot, y: safe)
        }
    }

    func clampedToScreenEdge(_ point: CGPoint, buffer: CGFloat = 15) -> CGPoint {
        let displays = DisplayService.shared.displays
        let mainH = NSScreen.main?.frame.height ?? 0
        for display in displays {
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

    // MARK: - Private methods

    private func prepareEventTap() {
        if !MouseTrackingService.shared.isTracking {
            _ = MouseTrackingService.shared.createTemporaryTap()
        }
    }

    private func removeTemporaryTap() {
        MouseTrackingService.shared.removeTemporaryTap()
    }

    private func currentDockDisplayID(dockPosition: DockPosition) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else { continue }
            let f = screen.frame
            let vf = screen.visibleFrame
            print("[DockRelocationService] currentDockDisplayID: screen=\(displayID) frame=\(f) visibleFrame=\(vf) dockPos=\(dockPosition)")
            switch dockPosition {
            case .bottom where vf.minY > f.minY:
                print("[DockRelocationService] currentDockDisplayID: found dock on \(displayID) (bottom)")
                return displayID
            case .left where vf.minX > f.minX:
                print("[DockRelocationService] currentDockDisplayID: found dock on \(displayID) (left)")
                return displayID
            case .right where vf.maxX < f.maxX:
                print("[DockRelocationService] currentDockDisplayID: found dock on \(displayID) (right)")
                return displayID
            default: continue
            }
        }

        return currentDockDisplayIDViaAX()
    }

    private func currentDockDisplayIDViaAX() -> CGDirectDisplayID? {
        let displays = DisplayService.shared.displays
        print("[DockRelocationService] currentDockDisplayID: falling back to AX")
        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            print("[DockRelocationService] currentDockDisplayID: dock app not found")
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("[DockRelocationService] currentDockDisplayID: AX windows query failed")
            return nil
        }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windows[0], kAXPositionAttribute as CFString, &positionValue
        ) == .success else {
            print("[DockRelocationService] currentDockDisplayID: AX position query failed")
            return nil
        }

        var position = CGPoint.zero
        guard let pv = positionValue, AXValueGetValue(pv as! AXValue, .cgPoint, &position) else { return nil }
        let found = displays.first { $0.frame.contains(position) }?.id
        print("[DockRelocationService] currentDockDisplayID: AX dock position=\(position) displayID=\(String(describing: found))")
        return found
    }

    private func sweepCursor(from start: CGPoint, to end: CGPoint, source: CGEventSource?) {
        CGWarpMouseCursorPosition(start)
        Thread.sleep(forTimeInterval: 0.03)

        for i in 0..<8 {
            let progress = CGFloat(i) / 7.0
            let current = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            CGWarpMouseCursorPosition(current)
            if let e = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: current,
                mouseButton: .left
            ) {
                e.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    private func dwellAtEdge(_ point: CGPoint, source: CGEventSource?) {
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(point)

        for _ in 0..<20 {
            if let e = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            ) {
                e.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.050)
        }
    }

    private func restoreCursor(to position: CGPoint) {
        CGAssociateMouseAndMouseCursorPosition(1)
        let safePosition = clampedToScreenEdge(position)
        CGWarpMouseCursorPosition(safePosition)
        print("[DockRelocationService] restoreCursor: restored to \(safePosition) (original: \(position))")
    }
}
