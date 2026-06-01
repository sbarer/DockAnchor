//
//  AppSettingsTests.swift
//  DockAnchorTests
//

import Foundation
import Testing
@testable import DockAnchor

@Suite("AppSettings", .serialized)
@MainActor
struct AppSettingsTests {

    // MARK: - extractBaseUUID

    @Test func testExtractBaseUUID_SN() {
        let settings = AppSettings.shared
        #expect(settings.extractBaseUUID(from: "ABCDEF-SN99999") == "ABCDEF")
    }

    @Test func testExtractBaseUUID_V() {
        let settings = AppSettings.shared
        #expect(settings.extractBaseUUID(from: "ABCDEF-V1M2") == "ABCDEF")
    }

    // MARK: - findAutoActivateProfile

    @Test func testFindAutoActivate_exactMatch() throws {
        let settings = AppSettings.shared
        let uuid = "test-exact-\(UUID().uuidString)"
        var profile = settings.createProfile(name: "AutoTest-Exact", autoActivate: true)
        profile.anchorDisplayUUID = uuid
        settings.updateProfile(profile)
        defer { settings.deleteProfile(profile) }

        let found = settings.findAutoActivateProfile(forDisplayUUID: uuid)
        #expect(found?.id == profile.id)
    }

    @Test func testFindAutoActivate_baseMatch() throws {
        let settings = AppSettings.shared
        let base = "test-base-\(UUID().uuidString)"
        let full = "\(base)-SN12345"
        var profile = settings.createProfile(name: "AutoTest-Base", autoActivate: true)
        profile.anchorDisplayUUID = full
        settings.updateProfile(profile)
        defer { settings.deleteProfile(profile) }

        // Search with base UUID — should match via stripped comparison
        let found = settings.findAutoActivateProfile(forDisplayUUID: base)
        #expect(found?.id == profile.id)
    }

    @Test func testFindAutoActivate_noMatch() {
        let settings = AppSettings.shared
        let found = settings.findAutoActivateProfile(forDisplayUUID: UUID().uuidString + "-NOPE")
        #expect(found == nil)
    }

    // MARK: - Profile CRUD

    @Test func testProfileCRUD_create() {
        let settings = AppSettings.shared
        let before = settings.profiles.count
        let profile = settings.createProfile(name: "CRUDCreate-\(UUID().uuidString)")
        defer { settings.deleteProfile(profile) }
        #expect(settings.profiles.count == before + 1)
        #expect(settings.profiles.contains { $0.id == profile.id })
    }

    @Test func testProfileCRUD_update() {
        let settings = AppSettings.shared
        var profile = settings.createProfile(name: "CRUDUpdate-Before")
        defer { settings.deleteProfile(profile) }
        profile.name = "CRUDUpdate-After"
        settings.updateProfile(profile)
        let found = settings.profiles.first { $0.id == profile.id }
        #expect(found?.name == "CRUDUpdate-After")
    }

    @Test func testProfileCRUD_delete() {
        let settings = AppSettings.shared
        let profile = settings.createProfile(name: "CRUDDelete-\(UUID().uuidString)")
        let beforeDelete = settings.profiles.count
        settings.deleteProfile(profile)
        #expect(settings.profiles.count == beforeDelete - 1)
        #expect(!settings.profiles.contains { $0.id == profile.id })
    }

    @Test func testProfileCRUD_deleteActiveProfile() {
        let settings = AppSettings.shared
        let profile = settings.createProfile(name: "CRUDDeleteActive-\(UUID().uuidString)")
        settings.activeProfileID = profile.id
        settings.deleteProfile(profile)
        #expect(settings.activeProfileID == nil)
    }
}
