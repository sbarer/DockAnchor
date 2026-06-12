//
//  MouseTrackingService.swift
//  DockAnchor
//

import Foundation
import Cocoa
import CoreGraphics

class MouseTrackingService {
    static let shared = MouseTrackingService()

    private(set) var isTracking: Bool = false
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    // Set by DockCoordinator (Phase 3)
    var onHotCornerDetected: (() -> Void)?
    var onStatusMessage: ((String) -> Void)?

    let cornerZoneSize: CGFloat = 60

    private init() {}

    // MARK: - Public API

    func startTracking() -> Bool {
        print("[MouseTrackingService] startTracking: called — AXTrusted=\(AXIsProcessTrusted()) isTracking=\(isTracking)")
        guard AXIsProcessTrusted() else {
            print("[MouseTrackingService] startTracking: FAILED — not AX trusted")
            onStatusMessage?("Please grant accessibility permissions in System Preferences")
            return false
        }

        guard !isTracking else {
            print("[MouseTrackingService] startTracking: already tracking, skipping")
            return true
        }

        installEventTap()

        guard eventTap != nil else {
            print("[MouseTrackingService] startTracking: FAILED — eventTap is nil after install")
            onStatusMessage?("Permission needs reset - remove and re-add app in Accessibility settings")
            return false
        }

        isTracking = true
        print("[MouseTrackingService] startTracking: SUCCESS — tap installed, isTracking=true")
        return true
    }

    func stopTracking() {
        print("[MouseTrackingService] stopTracking: isTracking=\(isTracking)")
        guard isTracking else { return }

        isTracking = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        print("[MouseTrackingService] stopTracking: done")
    }

    func createTemporaryTap() -> Bool {
        print("[MouseTrackingService] createTemporaryTap: called — eventTap exists=\(eventTap != nil)")
        guard eventTap == nil else { return false }

        let eventMask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let service = Unmanaged<MouseTrackingService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handleMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            print("[MouseTrackingService] createTemporaryTap: FAILED — tapCreate returned nil")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[MouseTrackingService] createTemporaryTap: SUCCESS")
        return true
    }

    func removeTemporaryTap() {
        print("[MouseTrackingService] removeTemporaryTap: isTracking=\(isTracking)")
        guard !isTracking else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    func isEventTapValid() -> Bool {
        guard let tap = eventTap else { return false }
        return CFMachPortIsValid(tap)
    }

    // MARK: - Internal (testable)

    func triggerZone(for display: DisplayInfo) -> CGRect {
        let dockPosition = DockCoordinator.shared.dockPosition
        switch dockPosition {
        case .bottom:
            return CGRect(x: display.frame.minX, y: display.frame.maxY - 15,
                          width: display.frame.width, height: 15)
        case .left:
            return CGRect(x: display.frame.minX, y: display.frame.minY,
                          width: 15, height: display.frame.height)
        case .right:
            return CGRect(x: display.frame.maxX - 15, y: display.frame.minY,
                          width: 15, height: display.frame.height)
        }
    }

    func cornerZones(for display: DisplayInfo) -> [CGRect] {
        let f = display.frame
        let s = cornerZoneSize
        let dockPosition = DockCoordinator.shared.dockPosition
        switch dockPosition {
        case .bottom:
            return [CGRect(x: f.minX, y: f.maxY - s, width: s, height: s),
                    CGRect(x: f.maxX - s, y: f.maxY - s, width: s, height: s)]
        case .left:
            return [CGRect(x: f.minX, y: f.minY, width: s, height: s),
                    CGRect(x: f.minX, y: f.maxY - s, width: s, height: s)]
        case .right:
            return [CGRect(x: f.maxX - s, y: f.minY, width: s, height: s),
                    CGRect(x: f.maxX - s, y: f.maxY - s, width: s, height: s)]
        }
    }

    func isInCornerZone(_ location: CGPoint, display: DisplayInfo) -> Bool {
        cornerZones(for: display).contains { $0.contains(location) }
    }

    func shouldBlock(at location: CGPoint) -> Bool {
        guard DockCoordinator.shared.isDockAnchored else { return false }
        let anchorID = DockCoordinator.shared.anchorDisplayID
        let allDisplays = DisplayService.shared.displays

        guard let currentDisplay = allDisplays.first(where: { $0.frame.contains(location) }) else {
            return false
        }

        guard currentDisplay.id != anchorID else {
            return false
        }

        let zone = triggerZone(for: currentDisplay)

        if AppSettings.shared.isHotCornersPreserved(forDisplayUUID: currentDisplay.uuid) &&
           isInCornerZone(location, display: currentDisplay) {
            print("[MouseTrackingService::shouldBlock]  hot corner — allowing through")
            onHotCornerDetected?()
            return false
        }

        if zone.contains(location) {
            print("[MouseTrackingService::shouldBlock] BLOCKING at \(currentDisplay.name)")
            DispatchQueue.main.async { [weak self] in
                self?.onStatusMessage?("Blocked dock movement attempt to \(currentDisplay.name)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.onStatusMessage?("Dock Anchor Deluxe Active - Monitoring mouse movement")
                }
            }
            return true
        }

        return false
    }

    // MARK: - Private

    private func installEventTap() {
        print("[MouseTrackingService] installEventTap: installing on thread=\(Thread.isMainThread ? "main" : "bg") runLoop=\(CFRunLoopGetCurrent() == CFRunLoopGetMain() ? "main" : "other")")
        let eventMask = CGEventMask(
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let service = Unmanaged<MouseTrackingService>.fromOpaque(refcon!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        DispatchQueue.main.async {
                            service.onStatusMessage?("Recovered event tap after system disable")
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                return service.handleMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            print("[MouseTrackingService] installEventTap: FAILED — tapCreate returned nil (AXTrusted=\(AXIsProcessTrusted()))")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[MouseTrackingService] installEventTap: SUCCESS — tap=\(tap)")
    }

    private func handleMouseEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .mouseMoved else { return Unmanaged.passUnretained(event) }
        return handleMouseMoved(event)
    }

    private func handleMouseMoved(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if shouldBlock(at: event.location) { return nil }
        return Unmanaged.passUnretained(event)
    }
}
