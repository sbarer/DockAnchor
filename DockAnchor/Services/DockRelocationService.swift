//
//  DockRelocationService.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics

// Extension to extract the CoreGraphics Direct Display ID from an NSScreen object
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID
    }
}

class DockRelocationService: @unchecked Sendable {
    static let shared = DockRelocationService()

    private let relocatingLock = NSLock()
    private var _isRelocating: Bool = false
    private(set) var isRelocating: Bool {
        get { relocatingLock.withLock { _isRelocating } }
        set { relocatingLock.withLock { _isRelocating = newValue } }
    }

    // Set by DockCoordinator (Phase 3)
    var onStatusMessage: ((String) -> Void)?
    var onRelocationComplete: (() -> Void)?

    private init() {}

    // MARK: - Public API

    func relocate(to display: DisplayInfo, dockPosition: DockPosition) async {
        // NSScreen.screens is main-thread-only; run both guards on MainActor
        let shouldSkip = await MainActor.run {
            isDockOnCorrectDisplay(display, dockPosition: dockPosition)
        }
        guard !shouldSkip else {
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

        print("[DockRelocationService:relocate] starting relocation to display='\(display.name)")
        isRelocating = true
        onStatusMessage?("Relocating dock to \(display.name)...")

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { continuation.resume(); return }

                self.prepareEventTap()

                DispatchQueue.main.sync { NSCursor.hide() }

                let source = CGEventSource(stateID: .hidSystemState)
                // Use physical dock position so sweep goes to the correct edge even if stored dockPosition is stale
                let effectivePosition = DispatchQueue.main.sync { self.detectCurrentDockState()?.position } ?? dockPosition
                let approachPoint = self.pastEdgePoint(for: display, dockPosition: effectivePosition)
                let edgePoint = self.triggerPoint(for: display, dockPosition: effectivePosition)

                print("[DockRelocationService:relocate] sweeping mouse \(approachPoint) → \(edgePoint)")

                self.sweepCursor(from: approachPoint, to: edgePoint, source: source)
                self.dwellAtEdge(edgePoint, source: source)
                self.restoreCursor(to: originalPosition)

                self.isRelocating = false
                self.removeTemporaryTap()

                DispatchQueue.main.sync { NSCursor.unhide() }

                DispatchQueue.main.async { [weak self] in
                    self?.onRelocationComplete?()
                    self?.onStatusMessage?("Dock relocated to \(display.name)")
                }

                continuation.resume()
            }
        }
    }

    func detectCurrentDockState() -> (displayID: CGDirectDisplayID, position: DockPosition)? {
        // 1. Determine the global dock edge alignment from macOS defaults
        let dockPositionString = UserDefaults.standard.string(forKey: "com.apple.dock.orientation") ?? "bottom"
        guard let currentPosition = DockPosition(rawValue: dockPositionString) else { return nil }

        // 2. Fetch all on-screen windows from the window server
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // 3. Isolate the main Dock bar window geometry
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName == "Dock",
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let dockRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // Filter out tiny UI elements like notification dots, download animations, or tooltips
            if dockRect.size.width < 100 && dockRect.size.height < 100 { continue }

            // 4. Calculate the true center point of the physical Dock bar
            let dockCenter = CGPoint(x: dockRect.midX, y: dockRect.midY)

            // 5. Correlate coordinate intersections against connected displays
            for screen in NSScreen.screens {
                // Translate the NSScreen layout over to CoreGraphics 2D space layout geometry
                let screenFrameCG = convertToCGCoordinateSpace(screenFrame: screen.frame)

                if screenFrameCG.contains(dockCenter) {
                    // If it hits, extract the target CGDirectDisplayID from the dictionary map
                    if let matchedID = screen.displayID {
                        return (displayID: matchedID, position: currentPosition)
                    }
                }
            }
        }

        return nil
    }

    // Transforms NSScreen (bottom-left origin) layout calculations over to CoreGraphics space (top-left origin)
    func convertToCGCoordinateSpace(screenFrame: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return screenFrame }
        let primaryHeight = primaryScreen.frame.size.height

        return CGRect(
            x: screenFrame.origin.x,
            y: primaryHeight - (screenFrame.origin.y + screenFrame.size.height),
            width: screenFrame.size.width,
            height: screenFrame.size.height
        )
    }

    func isDockOnCorrectDisplay(_ display: DisplayInfo, dockPosition: DockPosition) -> Bool {
        let displays = DisplayService.shared.displays
        guard displays.count > 1 else { return true }
        if let state = detectCurrentDockState() {
            let detectedName = DisplayService.shared.displays.first { $0.id == state.displayID }?.name ?? "unknown"
            let result = state.displayID == display.id
            print("[DockRelocationService:isDockOnCorrectDisplay] dock on \(detectedName), anchor \(display.name) → match=\(result)")
            return result
        }
        guard let currentID = currentDockDisplayID(dockPosition: dockPosition) else {
            print("[DockRelocationService:isDockOnCorrectDisplay] AX fallback returned nil — assuming not on anchor")
            return false
        }
        let foundName = DisplayService.shared.displays.first { $0.id == currentID }?.name ?? "unknown"
        let result = currentID == display.id
        print("[DockRelocationService:isDockOnCorrectDisplay] dock on \(foundName), anchor \(display.name) → match=\(result)")
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
        print("[DockRelocationService:safeEdgeOffset] '\(display.name)' range=\(rangeMin)..\(rangeMax) covered=\(covered) best=\(best)")
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
            switch dockPosition {
            case .bottom where vf.minY > f.minY:
                print("[DockRelocationService:currentDockDisplayID] dock on '\(screen.localizedName)' (bottom)")
                return displayID
            case .left where vf.minX > f.minX:
                print("[DockRelocationService:currentDockDisplayID] dock on '\(screen.localizedName)' (left)")
                return displayID
            case .right where vf.maxX < f.maxX:
                print("[DockRelocationService:currentDockDisplayID] dock on '\(screen.localizedName)' (right)")
                return displayID
            default: continue
            }
        }

        return currentDockDisplayIDViaAX()
    }

    private func currentDockDisplayIDViaAX() -> CGDirectDisplayID? {
        let displays = DisplayService.shared.displays
        print("[DockRelocationService:currentDockDisplayIDViaAX] falling back to AX")
        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            print("[DockRelocationService:currentDockDisplayIDViaAX] dock app not found")
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("[DockRelocationService:currentDockDisplayIDViaAX] AX windows query failed")
            return nil
        }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windows[0], kAXPositionAttribute as CFString, &positionValue
        ) == .success else {
            print("[DockRelocationService:currentDockDisplayIDViaAX] AX position query failed")
            return nil
        }

        var position = CGPoint.zero
        guard let pv = positionValue, AXValueGetValue(pv as! AXValue, .cgPoint, &position) else { return nil }
        let found = displays.first { $0.frame.contains(position) }
        print("[DockRelocationService:currentDockDisplayIDViaAX] dock at \(position) → '\(found?.name ?? "none")'")
        return found?.id
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
        defer { CGAssociateMouseAndMouseCursorPosition(1) }
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
        let safePosition = clampedToScreenEdge(position)
        CGWarpMouseCursorPosition(safePosition)
        print("[DockRelocationService:restoreCursor] restored mouse to \(safePosition) (original: \(position))")
    }
}
