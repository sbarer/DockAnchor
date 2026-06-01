//
//  MouseTrackingServiceTests.swift
//  DockAnchorTests
//

import Testing
@testable import DockAnchor
import CoreGraphics

@Suite("MouseTrackingService", .serialized)
struct MouseTrackingServiceTests {

    private let svc = MouseTrackingService.shared
    private let cornerSize: CGFloat = 60

    // Remote display well outside real screen coordinates
    private func remoteDisplay() -> DisplayInfo {
        let frame = CGRect(x: 200000, y: 200000, width: 2000, height: 1200)
        return DisplayInfo(id: 99998, uuid: "test-mouse-remote", serialNumber: nil,
                          frame: frame, name: "Mouse Test", isPrimary: false)
    }

    // MARK: - triggerZone

    @Test func testTriggerZone_bottom() {
        DockCoordinator.shared.dockPosition = .bottom
        let display = remoteDisplay()
        let zone = svc.triggerZone(for: display)
        #expect(zone.minX == display.frame.minX)
        #expect(zone.height == 10)
        #expect(zone.minY == display.frame.maxY - 10)
        #expect(zone.width == display.frame.width)
    }

    @Test func testTriggerZone_left() {
        DockCoordinator.shared.dockPosition = .left
        let display = remoteDisplay()
        let zone = svc.triggerZone(for: display)
        #expect(zone.minX == display.frame.minX)
        #expect(zone.width == 10)
        #expect(zone.minY == display.frame.minY)
        #expect(zone.height == display.frame.height)
    }

    @Test func testTriggerZone_right() {
        DockCoordinator.shared.dockPosition = .right
        let display = remoteDisplay()
        let zone = svc.triggerZone(for: display)
        #expect(zone.minX == display.frame.maxX - 10)
        #expect(zone.width == 10)
        #expect(zone.minY == display.frame.minY)
        #expect(zone.height == display.frame.height)
    }

    // MARK: - cornerZones

    @Test func testCornerZones_bottom() {
        DockCoordinator.shared.dockPosition = .bottom
        let display = remoteDisplay()
        let zones = svc.cornerZones(for: display)
        let f = display.frame
        let s = cornerSize
        #expect(zones.count == 2)
        // Bottom-left corner
        #expect(zones.contains { $0 == CGRect(x: f.minX, y: f.maxY - s, width: s, height: s) })
        // Bottom-right corner
        #expect(zones.contains { $0 == CGRect(x: f.maxX - s, y: f.maxY - s, width: s, height: s) })
    }

    @Test func testCornerZones_left() {
        DockCoordinator.shared.dockPosition = .left
        let display = remoteDisplay()
        let zones = svc.cornerZones(for: display)
        let f = display.frame
        let s = cornerSize
        #expect(zones.count == 2)
        // Top-left and bottom-left
        #expect(zones.contains { $0 == CGRect(x: f.minX, y: f.minY, width: s, height: s) })
        #expect(zones.contains { $0 == CGRect(x: f.minX, y: f.maxY - s, width: s, height: s) })
    }

    // MARK: - isInCornerZone

    @Test func testIsInCornerZone_true() {
        DockCoordinator.shared.dockPosition = .bottom
        let display = remoteDisplay()
        let f = display.frame
        // Point inside bottom-left corner zone
        let point = CGPoint(x: f.minX + 5, y: f.maxY - 5)
        #expect(svc.isInCornerZone(point, display: display))
    }

    @Test func testIsInCornerZone_false() {
        DockCoordinator.shared.dockPosition = .bottom
        let display = remoteDisplay()
        let f = display.frame
        // Centre of display — outside any corner zone
        let point = CGPoint(x: f.midX, y: f.midY)
        #expect(!svc.isInCornerZone(point, display: display))
    }
}
