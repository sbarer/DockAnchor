//
//  DisplayServiceTests.swift
//  DockAnchorTests
//

import Foundation
import Testing
@testable import DockAnchor

@Suite("DisplayService")
struct DisplayServiceTests {

    // MARK: - baseUUID

    @Test func testBaseUUID_stripsSerialSuffix() {
        #expect(DisplayService.shared.baseUUID(from: "ABCDEF-SN12345") == "ABCDEF")
    }

    @Test func testBaseUUID_stripsVendorSuffix() {
        #expect(DisplayService.shared.baseUUID(from: "ABCDEF-V1M2") == "ABCDEF")
    }

    @Test func testBaseUUID_unchanged() {
        #expect(DisplayService.shared.baseUUID(from: "ABCDEF") == "ABCDEF")
    }

    // MARK: - isAvailable

    @Test func testIsAvailable_exactMatch() async throws {
        try await Task.sleep(for: .milliseconds(200))
        let displays = DisplayService.shared.displays
        try #require(!displays.isEmpty, "Requires at least one connected display")
        #expect(DisplayService.shared.isAvailable(uuid: displays[0].uuid))
    }

    @Test func testIsAvailable_baseMatch() async throws {
        try await Task.sleep(for: .milliseconds(200))
        let displays = DisplayService.shared.displays
        try #require(!displays.isEmpty, "Requires at least one connected display")
        let base = DisplayService.shared.baseUUID(from: displays[0].uuid)
        // base UUID should resolve to the display (either exact or base match)
        #expect(DisplayService.shared.isAvailable(uuid: base))
    }

    @Test func testIsAvailable_noMatch() {
        #expect(!DisplayService.shared.isAvailable(uuid: UUID().uuidString + "-UNKNOWN"))
    }

    // MARK: - canonicalUUID

    @Test func testCanonicalUUID_exactMatch() async throws {
        try await Task.sleep(for: .milliseconds(200))
        let displays = DisplayService.shared.displays
        try #require(!displays.isEmpty, "Requires at least one connected display")
        let uuid = displays[0].uuid
        #expect(DisplayService.shared.canonicalUUID(matching: uuid) == uuid)
    }

    @Test func testCanonicalUUID_baseMatch() async throws {
        try await Task.sleep(for: .milliseconds(200))
        let displays = DisplayService.shared.displays
        try #require(!displays.isEmpty, "Requires at least one connected display")
        let full = displays[0].uuid
        let base = DisplayService.shared.baseUUID(from: full)
        let canonical = DisplayService.shared.canonicalUUID(matching: base)
        // Canonical should be the stored UUID (which may be full or base)
        #expect(canonical != nil)
        #expect(DisplayService.shared.baseUUID(from: canonical!) == base)
    }
}
