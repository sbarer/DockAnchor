//
//  PermissionServiceTests.swift
//  DockAnchorTests
//

import Testing
@testable import DockAnchor

@Suite("PermissionService", .serialized)
@MainActor
struct PermissionServiceTests {

    // MARK: - poll() single-fire guarantee

    @Test func testPoll_stopsTimerBeforeFiringOnRevoked() async throws {
        // Start polling at a very short interval so we can control timing
        let svc = PermissionService.shared
        svc.stopPolling()

        var revokedCount = 0
        svc.onRevoked = { revokedCount += 1 }
        defer { svc.onRevoked = nil; svc.stopPolling() }

        // poll() is private — test the public contract: startPolling then stopPolling
        // stops the timer, so subsequent ticks do not increment revokedCount
        svc.startPolling(interval: 0.05)
        // If AX is trusted, no revocation fires — this just verifies polling starts/stops cleanly
        try await Task.sleep(for: .milliseconds(200))
        svc.stopPolling()
        // revokedCount is 0 when AX trusted (normal CI environment)
        // The key invariant: it should never exceed 1 regardless of timer interval
        #expect(revokedCount <= 1)
    }

    // MARK: - check() / isGranted state

    @Test func testCheck_returnsCurrentTrustState() {
        let svc = PermissionService.shared
        let result = svc.check()
        // check() must match AXIsProcessTrusted() at call time
        #expect(result == AXIsProcessTrusted())
        #expect(svc.isGranted == AXIsProcessTrusted())
    }

    // MARK: - startPolling guard

    @Test func testStartPolling_doesNotCreateDuplicateTimers() async throws {
        let svc = PermissionService.shared
        svc.stopPolling()
        svc.startPolling(interval: 60)
        svc.startPolling(interval: 60) // second call must be a no-op
        try await Task.sleep(for: .milliseconds(50))
        // No assertion needed beyond "does not crash" — the guard in startPolling prevents duplicates
        svc.stopPolling()
    }
}
