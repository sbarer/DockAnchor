//
//  PermissionManager.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices

extension DockMonitor {

    func requestAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Accessibility permissions required"
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.needsPermissionReset = false
            }
        }

        return trusted
    }

    func promptForAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.verifyPermissionsAndTapValidity()
        }
    }

    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func verifyPermissionsAndTapValidity() {
        guard isMonitoring else { return }

        if !checkAccessibilityPermissions() {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Accessibility permissions revoked - stopping monitoring"
                self?.stopMonitoring()
            }
            return
        }

        if let tap = eventTap, !CFMachPortIsValid(tap) {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Event tap invalidated - stopping monitoring"
                self?.stopMonitoring()
            }
        }
    }
}
