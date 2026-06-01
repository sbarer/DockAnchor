//
//  PermissionService.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices

class PermissionService {
    static let shared = PermissionService()

    private(set) var isGranted: Bool = false

    // Set by DockCoordinator (Phase 3) — called when permission is revoked while monitoring
    var onRevoked: (() -> Void)?

    private var pollTimer: Timer?

    private init() {
        isGranted = AXIsProcessTrusted()
    }

    // MARK: - Public API

    func check() -> Bool {
        isGranted = AXIsProcessTrusted()
        return isGranted
    }

    func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startPolling(interval: TimeInterval) {
        guard pollTimer == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pollTimer == nil else { return }
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Private

    private func poll() {
        guard !AXIsProcessTrusted() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onRevoked?()
        }
    }
}
