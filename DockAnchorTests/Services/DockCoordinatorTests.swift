//
//  DockCoordinatorTests.swift
//  DockAnchorTests
//

import Testing
@testable import DockAnchor

@Suite("DockCoordinator", .serialized)
@MainActor
struct DockCoordinatorTests {

    // MARK: - Sleep / wake lifecycle

    @Test func testHandleSystemSleep_stopsMonitoring() async throws {
        let coord = DockCoordinator.shared
        // Monitoring must be active first (requires AX permission in CI — skip if not trusted)
        guard AXIsProcessTrusted() else { return }
        coord.startMonitoring()
        try #require(coord.isActive, "startMonitoring must succeed for this test")
        coord.handleSystemSleep()
        #expect(!coord.isActive)
    }

    @Test func testHandleSystemWake_restartsMonitoring() async throws {
        let coord = DockCoordinator.shared
        guard AXIsProcessTrusted() else { return }
        // Ensure monitoring is stopped before wake
        coord.stopMonitoring()
        #expect(!coord.isActive)
        coord.handleSystemWake()
        // handleSystemWake schedules startMonitoring after 1s — wait for it
        try await Task.sleep(for: .milliseconds(1200))
        #expect(coord.isActive)
        coord.stopMonitoring()
    }

    @Test func testHandleSystemWake_doesNotRestartWhenRunInBackgroundFalse() async throws {
        let coord = DockCoordinator.shared
        let original = AppSettings.shared.runInBackground
        AppSettings.shared.runInBackground = false
        defer { AppSettings.shared.runInBackground = original }

        coord.stopMonitoring()
        coord.handleSystemWake()
        try await Task.sleep(for: .milliseconds(1200))
        #expect(!coord.isActive)
    }

    // MARK: - relocateDock isActive guard

    @Test func testRelocateDock_noopsWhenInactive() {
        let coord = DockCoordinator.shared
        coord.stopMonitoring()
        #expect(!coord.isActive)
        let before = DockRelocationService.shared.isRelocating
        coord.relocateDock()
        // Relocation must not have started since monitoring is off
        #expect(DockRelocationService.shared.isRelocating == before)
    }

    // MARK: - AnchorState sync

    @Test func testAnchorStateSyncs_onDockPositionChange() {
        let coord = DockCoordinator.shared
        coord.dockPosition = .left
        #expect(MouseTrackingService.shared.anchorState.dockPosition == .left)
        coord.dockPosition = .bottom
        #expect(MouseTrackingService.shared.anchorState.dockPosition == .bottom)
    }

    @Test func testAnchorStateSyncs_onAnchorDisplayChange() {
        let coord = DockCoordinator.shared
        let originalUUID = coord.anchorDisplayUUID
        defer { coord.anchorDisplayUUID = originalUUID }
        coord.anchorDisplayUUID = "test-uuid-sync"
        #expect(MouseTrackingService.shared.anchorState.anchorDisplayID == coord.anchorDisplayID)
    }
}
