//
//  DockResizeServiceTests.swift
//  DockAnchorTests
//

import Testing
@testable import DockAnchor

@Suite("DockResizeService")
struct DockResizeServiceTests {

    private let svc = DockResizeService.shared

    // MARK: - parsePosition

    @Test func testParsePosition_bottom() {
        #expect(svc.parsePosition("bottom") == .bottom)
    }

    @Test func testParsePosition_left() {
        #expect(svc.parsePosition("left") == .left)
    }

    @Test func testParsePosition_right() {
        #expect(svc.parsePosition("right") == .right)
    }

    @Test func testParsePosition_unknown() {
        #expect(svc.parsePosition("top") == .bottom)
        #expect(svc.parsePosition("") == .bottom)
        #expect(svc.parsePosition("invalid") == .bottom)
    }

    // MARK: - parseTileSize

    @Test func testParseTileSize_valid() {
        #expect(svc.parseTileSize("48") == 48)
        #expect(svc.parseTileSize("32") == 32)
        #expect(svc.parseTileSize("5") == 5)
    }

    @Test func testParseTileSize_malformed() {
        #expect(svc.parseTileSize("abc") == 48)
        #expect(svc.parseTileSize("") == 48)
        #expect(svc.parseTileSize("12.5") == 48)
    }
}
