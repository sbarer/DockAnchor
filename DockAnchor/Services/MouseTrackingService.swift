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
        guard AXIsProcessTrusted() else {
            onStatusMessage?("Please grant accessibility permissions in System Preferences")
            return false
        }

        guard !isTracking else { return true }

        installEventTap()

        guard eventTap != nil else {
            onStatusMessage?("Permission needs reset - remove and re-add app in Accessibility settings")
            return false
        }

        isTracking = true
        return true
    }

    func stopTracking() {
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
    }

    func createTemporaryTap() -> Bool {
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

        guard let tap = eventTap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func removeTemporaryTap() {
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
            return CGRect(x: display.frame.minX, y: display.frame.maxY - 10,
                          width: display.frame.width, height: 10)
        case .left:
            return CGRect(x: display.frame.minX, y: display.frame.minY,
                          width: 10, height: display.frame.height)
        case .right:
            return CGRect(x: display.frame.maxX - 10, y: display.frame.minY,
                          width: 10, height: display.frame.height)
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
        let anchorID = DockCoordinator.shared.anchorDisplayID
        for display in DisplayService.shared.displays {
            if display.id == anchorID { continue }

            if AppSettings.shared.isHotCornersPreserved(forDisplayUUID: display.uuid) &&
               isInCornerZone(location, display: display) {
                onHotCornerDetected?()
                return false
            }

            if triggerZone(for: display).contains(location) {
                DispatchQueue.main.async { [weak self] in
                    self?.onStatusMessage?("Blocked dock movement attempt to \(display.name)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.onStatusMessage?("Dock Anchor Active - Monitoring mouse movement")
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Private

    private func installEventTap() {
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

        guard let tap = eventTap else { return }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
