//
//  DisplayManager.swift
//  DockAnchor
//

import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics

extension DockMonitor {

    func updateAvailableDisplays() {
        let newDisplays = getAllDisplays()
        availableDisplays = newDisplays

        detectCurrentDockPosition()
        validateCurrentAnchorDisplay()
        updateAnchoredDisplayName()

        DispatchQueue.main.async {
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .displaysDidChange, object: nil)
        }
    }

    func validateCurrentAnchorDisplay() {
        if availableDisplays.count == 1, let onlyDisplay = availableDisplays.first {
            if anchorDisplayUUID != onlyDisplay.uuid {
                anchorDisplayUUID = onlyDisplay.uuid
                AppSettings.shared.selectedDisplayUUID = onlyDisplay.uuid
            }
            return
        }

        let isAnchorDisplayAvailable = isDisplayAvailable(uuid: anchorDisplayUUID)

        if !isAnchorDisplayAvailable {
            let defaultUUID = getDefaultAnchorDisplayUUID()
            anchorDisplayUUID = defaultUUID
            let defaultName = AppSettings.shared.defaultAnchorDisplay == .builtIn ? "Built-in" : "Primary"
            statusMessage = "Anchor display unavailable - temporarily using \(defaultName)"

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                if self.isActive {
                    self.statusMessage = "Dock Anchor Active - Monitoring mouse movement"
                } else {
                    self.statusMessage = "Dock Anchor Ready"
                }
            }
        } else if let currentUUID = getCurrentUUID(matching: anchorDisplayUUID),
                  currentUUID != anchorDisplayUUID {
            anchorDisplayUUID = currentUUID
        }
    }

    func updateAnchoredDisplayName() {
        if let display = availableDisplays.first(where: { $0.uuid == anchorDisplayUUID }) {
            anchoredDisplay = display.name
        }
    }

    private func getAllDisplays() -> [DisplayInfo] {
        var displays: [DisplayInfo] = []

        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else {
            return displays
        }

        let mainDisplayID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let displayID = displayIDs[i]
            let uuid = Self.getDisplayUUID(for: displayID)
            let serialNumber = Self.getSerialNumber(for: displayID)
            let frame = CGDisplayBounds(displayID)
            let name = getDisplayName(for: displayID)
            let isPrimary = displayID == mainDisplayID

            displays.append(DisplayInfo(id: displayID, uuid: uuid, serialNumber: serialNumber, frame: frame, name: name, isPrimary: isPrimary))
        }

        displays.sort { d1, d2 in
            if d1.isPrimary && !d2.isPrimary { return true }
            if !d1.isPrimary && d2.isPrimary { return false }
            return d1.frame.minX < d2.frame.minX
        }

        return displays
    }

    private func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? CGDirectDisplayID) == displayID }) {
            let isPrimary = displayID == CGMainDisplayID()
            return isPrimary ? "\(screen.localizedName) (Primary)" : screen.localizedName
        }
        if displayID == CGMainDisplayID() { return "Primary Display" }
        let frame = CGDisplayBounds(displayID)
        let mainFrame = CGDisplayBounds(CGMainDisplayID())
        if frame.minX > mainFrame.maxX { return "Right Display" }
        if frame.maxX < mainFrame.minX { return "Left Display" }
        if frame.minY > mainFrame.maxY { return "Bottom Display" }
        if frame.maxY < mainFrame.minY { return "Top Display" }
        return "Secondary Display"
    }

    func refreshDisplays() {
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else { return }

        var newDisplays: [DisplayInfo] = []

        for i in 0..<displayCount {
            let displayID = displayIDs[Int(i)]
            let frame = CGDisplayBounds(displayID)
            if frame.width == 0 || frame.height == 0 { continue }

            newDisplays.append(DisplayInfo(
                id: displayID,
                uuid: Self.getDisplayUUID(for: displayID),
                serialNumber: Self.getSerialNumber(for: displayID),
                frame: frame,
                name: getDisplayName(for: displayID),
                isPrimary: displayID == CGMainDisplayID()
            ))
        }

        newDisplays.sort { d1, d2 in
            if d1.isPrimary { return true }
            if d2.isPrimary { return false }
            return d1.frame.minX < d2.frame.minX
        }

        DispatchQueue.main.async {
            self.availableDisplays = newDisplays
            self.validateCurrentAnchorDisplay()
            self.updateAnchoredDisplayName()
        }
    }

    func setupDisplayConfigurationMonitoring() {
        CGDisplayRegisterReconfigurationCallback({ (displayID, flags, userInfo) in
            guard let userInfo = userInfo else { return }
            let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleDisplayConfigurationChange(displayID: displayID, flags: flags)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func handleDisplayConfigurationChange(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if flags.contains(.addFlag) {
                self.statusMessage = "New display detected - updating available displays"
                self.updateAvailableDisplays()

                let connectedDisplayUUID = Self.getDisplayUUID(for: displayID)
                var profileActivated = false

                if let profile = AppSettings.shared.findAutoActivateProfile(forDisplayUUID: connectedDisplayUUID) {
                    let currentAnchorMatchesProfile = AppSettings.shared.selectedDisplayUUID == profile.anchorDisplayUUID
                    if AppSettings.shared.activeProfileID != profile.id || !currentAnchorMatchesProfile {
                        AppSettings.shared.switchToProfile(profile)
                        self.statusMessage = "Auto-activated profile: \(profile.name)"
                        profileActivated = true
                    }
                }

                if !profileActivated {
                    if AppSettings.shared.activeProfileID == nil && AppSettings.shared.defaultAnchorDisplay == .main {
                        let mainDisplayUUID = self.getMainDisplayUUID()
                        if self.anchorDisplayUUID != mainDisplayUUID {
                            self.anchorDisplayUUID = mainDisplayUUID
                            AppSettings.shared.selectedDisplayUUID = mainDisplayUUID
                            self.updateAnchoredDisplayName()
                            self.statusMessage = "Main display changed - anchoring to \(self.anchoredDisplay)"
                        }
                    } else {
                        let userPreferredUUID = AppSettings.shared.selectedDisplayUUID
                        if self.isDisplayAvailable(uuid: userPreferredUUID),
                           let currentUUID = self.getCurrentUUID(matching: userPreferredUUID),
                           self.anchorDisplayUUID != currentUUID {
                            self.anchorDisplayUUID = currentUUID
                            self.updateAnchoredDisplayName()
                            self.statusMessage = "Preferred display reconnected - restoring anchor to \(self.anchoredDisplay)"
                            if currentUUID != userPreferredUUID {
                                AppSettings.shared.selectedDisplayUUID = currentUUID
                            }
                        }
                    }

                    if AppSettings.shared.autoRelocateDock {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.relocateDockToAnchoredDisplay()
                        }
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }
                    self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                }

            } else if flags.contains(.removeFlag) {
                self.statusMessage = "Display removed - updating available displays"
                self.updateAvailableDisplays()

                if !self.availableDisplays.contains(where: { $0.uuid == self.anchorDisplayUUID }) {
                    let defaultUUID = self.getDefaultAnchorDisplayUUID()
                    self.anchorDisplayUUID = defaultUUID
                    self.updateAnchoredDisplayName()
                    let defaultName = AppSettings.shared.defaultAnchorDisplay == .builtIn ? "Built-in" : "Primary"
                    self.statusMessage = "Anchor display disconnected - temporarily using \(defaultName)"
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }
                    self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                }

            } else if flags.contains(.enabledFlag) || flags.contains(.disabledFlag) {
                self.updateAvailableDisplays()

            } else if flags.contains(.movedFlag) || flags.contains(.desktopShapeChangedFlag) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    self.updateAvailableDisplays()
                    self.statusMessage = "Display arrangement updated"
                    self.objectWillChange.send()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self else { return }
                        self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                    }
                }

            } else if flags.contains(.setMainFlag) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    self.updateAvailableDisplays()

                    if AppSettings.shared.activeProfileID == nil && AppSettings.shared.defaultAnchorDisplay == .main {
                        let mainDisplayUUID = self.getMainDisplayUUID()
                        if self.anchorDisplayUUID != mainDisplayUUID {
                            self.anchorDisplayUUID = mainDisplayUUID
                            AppSettings.shared.selectedDisplayUUID = mainDisplayUUID
                            self.updateAnchoredDisplayName()
                            self.statusMessage = "Main display changed - anchoring to \(self.anchoredDisplay)"

                            if AppSettings.shared.autoRelocateDock {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                    self?.relocateDockToAnchoredDisplay()
                                }
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                                guard let self = self else { return }
                                self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
                            }
                        }
                    }
                }

            } else if flags.contains(.setModeFlag) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateAvailableDisplays()
                }
            }
        }
    }
}
