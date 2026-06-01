//
//  DockRelocationServiceTests.swift
//  DockAnchorTests
//

import AppKit
import Foundation
import Testing
@testable import DockAnchor
import CoreGraphics

@Suite("DockRelocationService")
struct DockRelocationServiceTests {

    private let svc = DockRelocationService.shared

    // MARK: - subtractRanges

    @Test func testSubtractRanges_noOverlap() {
        let result = svc.subtractRanges(from: (0, 100), subtract: [(200, 300)])
        #expect(result.count == 1)
        #expect(result[0].0 == 0 && result[0].1 == 100)
    }

    @Test func testSubtractRanges_partialLeft() {
        let result = svc.subtractRanges(from: (0, 100), subtract: [(0, 40)])
        #expect(result.count == 1)
        #expect(result[0].0 == 40 && result[0].1 == 100)
    }

    @Test func testSubtractRanges_partialRight() {
        let result = svc.subtractRanges(from: (0, 100), subtract: [(60, 100)])
        #expect(result.count == 1)
        #expect(result[0].0 == 0 && result[0].1 == 60)
    }

    @Test func testSubtractRanges_fullCoverage() {
        let result = svc.subtractRanges(from: (0, 100), subtract: [(0, 100)])
        #expect(result.isEmpty)
    }

    @Test func testSubtractRanges_multipleSegments() {
        let result = svc.subtractRanges(from: (0, 100), subtract: [(30, 60)])
        #expect(result.count == 2)
        let sorted = result.sorted { $0.0 < $1.0 }
        #expect(sorted[0].0 == 0 && sorted[0].1 == 30)
        #expect(sorted[1].0 == 60 && sorted[1].1 == 100)
    }

    // MARK: - safeEdgeOffset (isolated display at remote coordinates)

    private func remoteDisplay() -> DisplayInfo {
        let frame = CGRect(x: 200000, y: 200000, width: 2000, height: 1200)
        return DisplayInfo(id: 99997, uuid: "test-remote", serialNumber: nil,
                          frame: frame, name: "Remote Test", isPrimary: false)
    }

    @Test func testSafeEdgeOffset_noAdjacentDisplays() {
        // No real display is adjacent to coords at 200000+, so full range is free
        let display = remoteDisplay()
        let offset = svc.safeEdgeOffset(for: display, dockPosition: .bottom)
        let expectedMid = (display.frame.minX + display.frame.maxX) / 2
        #expect(offset == expectedMid)
    }

    @Test func testSafeEdgeOffset_adjacentDisplay() async throws {
        let displays = DisplayService.shared.displays
        try #require(displays.count >= 2, "Requires 2+ connected displays")
        let d0 = displays[0]
        // Offset should be within d0's x range
        let offset = svc.safeEdgeOffset(for: d0, dockPosition: .bottom)
        #expect(offset >= d0.frame.minX)
        #expect(offset <= d0.frame.maxX)
    }

    // MARK: - triggerPoint (using remote isolated display)

    @Test func testTriggerPoint_bottom() {
        let display = remoteDisplay()
        let point = svc.triggerPoint(for: display, dockPosition: .bottom)
        #expect(point.y == display.frame.maxY - 1)
        #expect(point.x == (display.frame.minX + display.frame.maxX) / 2)
    }

    @Test func testTriggerPoint_left() {
        let display = remoteDisplay()
        let point = svc.triggerPoint(for: display, dockPosition: .left)
        #expect(point.x == display.frame.minX + 1)
        #expect(point.y == (display.frame.minY + display.frame.maxY) / 2)
    }

    @Test func testTriggerPoint_right() {
        let display = remoteDisplay()
        let point = svc.triggerPoint(for: display, dockPosition: .right)
        #expect(point.x == display.frame.maxX - 1)
        #expect(point.y == (display.frame.minY + display.frame.maxY) / 2)
    }

    @Test func testPastEdgePoint_bottom() {
        let display = remoteDisplay()
        let point = svc.pastEdgePoint(for: display, dockPosition: .bottom)
        #expect(point.y == display.frame.maxY + 20)
        #expect(point.x == (display.frame.minX + display.frame.maxX) / 2)
    }

    // MARK: - clampedToScreenEdge

    @Test func testClampedToScreenEdge_insideDisplay() async throws {
        try await Task.sleep(for: .milliseconds(200))
        let displays = DisplayService.shared.displays
        try #require(!displays.isEmpty, "Requires at least one connected display")
        let f = displays[0].frame
        let mainH = NSScreen.main?.frame.height ?? 0
        // A point near the top-left corner of the display in CG coords
        let cornerPoint = CGPoint(x: f.minX + 5, y: mainH - f.maxY + 5)
        let clamped = svc.clampedToScreenEdge(cornerPoint, buffer: 15)
        #expect(clamped.x >= f.minX + 15)
    }
}
