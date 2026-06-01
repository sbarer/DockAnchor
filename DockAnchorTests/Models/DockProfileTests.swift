//
//  DockProfileTests.swift
//  DockAnchorTests
//

import Testing
@testable import DockAnchor
import Foundation

@Suite("DockProfile")
struct DockProfileTests {

    @Test func testCodableRoundTrip_allFields() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let original = DockProfile(
            id: id,
            name: "My Profile",
            anchorDisplayUUID: "UUID-SN12345",
            createdAt: date,
            autoActivate: true,
            dockPosition: .left,
            dockTileSize: 36
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DockProfile.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "My Profile")
        #expect(decoded.anchorDisplayUUID == "UUID-SN12345")
        #expect(decoded.autoActivate == true)
        #expect(decoded.dockPosition == .left)
        #expect(decoded.dockTileSize == 36)
    }

    @Test func testCodableRoundTrip_nilOptionals() throws {
        let original = DockProfile(
            name: "Minimal",
            anchorDisplayUUID: "UUID-PLAIN",
            dockPosition: nil,
            dockTileSize: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DockProfile.self, from: data)

        #expect(decoded.name == "Minimal")
        #expect(decoded.dockPosition == nil)
        #expect(decoded.dockTileSize == nil)
        #expect(decoded.autoActivate == false)
    }

    @Test func testDecoderMigration_missingAutoActivate() throws {
        // Legacy JSON without autoActivate field
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy",
            "anchorDisplayUUID": "OLD-UUID",
            "createdAt": 1000000
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(DockProfile.self, from: data)
        #expect(decoded.autoActivate == false)
        #expect(decoded.dockPosition == nil)
        #expect(decoded.dockTileSize == nil)
    }
}
