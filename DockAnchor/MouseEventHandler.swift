//
//  MouseEventHandler.swift
//  DockAnchor
//

import Foundation
import Cocoa
import CoreGraphics

extension DockMonitor {

    func startMonitoring() {
        guard requestAccessibilityPermissions() else {
            statusMessage = "Please grant accessibility permissions in System Preferences"
            return
        }

        guard !isMonitoring else { return }

        updateAvailableDisplays()

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
                let monitor = Unmanaged<DockMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        DispatchQueue.main.async {
                            monitor.statusMessage = "Recovered event tap after system disable"
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                return monitor.handleMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            needsPermissionReset = true
            statusMessage = "Permission needs reset - remove and re-add app in Accessibility settings"
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isMonitoring = true
        startPermissionMonitoring()
        DispatchQueue.main.async { [weak self] in
            self?.isActive = true
            self?.statusMessage = "Dock Anchor Active - Monitoring mouse movement"
        }
    }

    func stopMonitoring() {
        stopPermissionMonitoring()
        guard isMonitoring else { return }

        isMonitoring = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.isActive = false
            self?.statusMessage = "Dock Anchor Stopped"
        }
    }

    func createEventTapForRelocation() -> Bool {
        guard eventTap == nil else { return false }

        let eventMask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<DockMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func removeTemporaryEventTap() {
        guard !isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    private func handleMouseEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .mouseMoved else { return Unmanaged.passUnretained(event) }
        return shouldBlockDockMovement(at: event.location) ? nil : Unmanaged.passUnretained(event)
    }

    private func shouldBlockDockMovement(at location: CGPoint) -> Bool {
        for display in availableDisplays {
            if display.id == anchorDisplayID { continue }

            if AppSettings.shared.isHotCornersPreserved(forDisplayUUID: display.uuid) && isLocationInCornerZone(location, for: display) {
                startHotCornerDockWatch()
                return false
            }

            if getDockTriggerZone(for: display).contains(location) {
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "Blocked dock movement attempt to \(display.name)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.statusMessage = "Dock Anchor Active - Monitoring mouse movement"
                    }
                }
                return true
            }
        }
        return false
    }

    private func getDockTriggerZone(for display: DisplayInfo) -> CGRect {
        switch dockPosition {
        case .bottom: return CGRect(x: display.frame.minX, y: display.frame.maxY - 10, width: display.frame.width, height: 10)
        case .left:   return CGRect(x: display.frame.minX, y: display.frame.minY, width: 10, height: display.frame.height)
        case .right:  return CGRect(x: display.frame.maxX - 10, y: display.frame.minY, width: 10, height: display.frame.height)
        }
    }

    private func getCornerZones(for display: DisplayInfo) -> [CGRect] {
        let f = display.frame
        let s = cornerZoneSize
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

    private func isLocationInCornerZone(_ location: CGPoint, for display: DisplayInfo) -> Bool {
        getCornerZones(for: display).contains { $0.contains(location) }
    }

    private func startHotCornerDockWatch() {
        guard hotCornerWatchTimer == nil else { return }
        print("[DockAnchor] startHotCornerDockWatch: starting 2s initial delay")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.hotCornerWatchTimer == nil else { return }
            // One-shot delay before first check — gives macOS time to move the dock after hot corner activates
            self.hotCornerWatchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("[DockAnchor] hotCornerWatch: initial delay elapsed, starting 1s poll (anchorID=\(self.anchorDisplayID))")
                var attempt = 0
                self.hotCornerWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    let onAnchor = self.isDockOnAnchoredDisplay()
                    print("[DockAnchor] hotCornerWatch tick \(attempt + 1) — isDockOnAnchor=\(onAnchor) isRelocating=\(self.isRelocating) anchorID=\(self.anchorDisplayID)")
                    if onAnchor {
                        print("[DockAnchor] hotCornerWatch: dock confirmed on anchor, stopping timer")
                        self.hotCornerWatchTimer?.invalidate()
                        self.hotCornerWatchTimer = nil
                    } else if attempt >= 5 {
                        print("[DockAnchor] hotCornerWatch: giving up after \(attempt) attempts")
                        self.hotCornerWatchTimer?.invalidate()
                        self.hotCornerWatchTimer = nil
                    } else if !self.isRelocating {
                        attempt += 1
                        print("[DockAnchor] hotCornerWatch: triggering relocation attempt \(attempt)")
                        self.relocateDockToAnchoredDisplay()
                    }
                }
            }
        }
    }
}
