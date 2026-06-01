//
//  DisplayService.swift
//  DockAnchor
//

import Foundation
import Cocoa
import CoreGraphics
import IOKit

// MARK: - Private free functions

private func getDisplaySerialNumber(for displayID: CGDirectDisplayID) -> UInt32? {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("IODisplayConnect")

    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return nil
    }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }

        if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] {
            if let vendorID = info[kDisplayVendorID] as? Int,
               let productID = info[kDisplayProductID] as? Int,
               let serialNumber = info[kDisplaySerialNumber] as? Int {

                let displayVendor = CGDisplayVendorNumber(displayID)
                let displayProduct = CGDisplayModelNumber(displayID)
                let displaySerial = CGDisplaySerialNumber(displayID)

                if UInt32(vendorID) == displayVendor && UInt32(productID) == displayProduct {
                    if serialNumber != 0 {
                        return UInt32(serialNumber)
                    } else if displaySerial != 0 {
                        return displaySerial
                    }
                }
            }
        }
    }

    let serial = CGDisplaySerialNumber(displayID)
    return serial != 0 ? serial : nil
}

private func createStableDisplayFingerprint(for displayID: CGDirectDisplayID) -> String {
    var uuidString = "DisplayID-\(displayID)"
    if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
        let uuidRef = uuid.takeRetainedValue()
        uuidString = CFUUIDCreateString(nil, uuidRef) as String
    }

    if let serialNumber = getDisplaySerialNumber(for: displayID), serialNumber != 0 {
        return "\(uuidString)-SN\(serialNumber)"
    }

    let vendor = CGDisplayVendorNumber(displayID)
    let model = CGDisplayModelNumber(displayID)
    if vendor != 0 || model != 0 {
        return "\(uuidString)-V\(vendor)M\(model)"
    }

    return uuidString
}

// MARK: - DisplayService

class DisplayService: ObservableObject {
    static let shared = DisplayService()

    @Published private(set) var displays: [DisplayInfo] = []

    // Set by DockCoordinator (Phase 3)
    var onDisplayAdded: ((DisplayInfo) -> Void)?
    var onDisplayRemoved: ((CGDirectDisplayID) -> Void)?
    var onLayoutChanged: (() -> Void)?

    private init() {
        registerReconfigurationCallback()
        refresh()
    }

    // MARK: - Public API

    func display(forUUID uuid: String) -> DisplayInfo? {
        if let exact = displays.first(where: { $0.uuid == uuid }) {
            return exact
        }
        let base = baseUUID(from: uuid)
        return displays.first { baseUUID(from: $0.uuid) == base }
    }

    func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        display(forUUID: uuid)?.id
    }

    func uuid(forDisplayID id: CGDirectDisplayID) -> String? {
        displays.first { $0.id == id }?.uuid
    }

    func isAvailable(uuid: String) -> Bool {
        if displays.contains(where: { $0.uuid == uuid }) { return true }
        let base = baseUUID(from: uuid)
        return displays.contains { baseUUID(from: $0.uuid) == base }
    }

    func canonicalUUID(matching uuid: String) -> String? {
        if let exact = displays.first(where: { $0.uuid == uuid }) {
            return exact.uuid
        }
        let base = baseUUID(from: uuid)
        return displays.first { baseUUID(from: $0.uuid) == base }?.uuid
    }

    static func fingerprint(for displayID: CGDirectDisplayID) -> String {
        createStableDisplayFingerprint(for: displayID)
    }

    static func serialNumber(for displayID: CGDirectDisplayID) -> UInt32? {
        getDisplaySerialNumber(for: displayID)
    }

    // MARK: - Internal (testable)

    func baseUUID(from fingerprint: String) -> String {
        if let snRange = fingerprint.range(of: "-SN") {
            return String(fingerprint[..<snRange.lowerBound])
        }
        if let vRange = fingerprint.range(of: "-V") {
            return String(fingerprint[..<vRange.lowerBound])
        }
        return fingerprint
    }

    // MARK: - Private

    private func refresh() {
        let newDisplays = enumerate()
        DispatchQueue.main.async { [weak self] in
            self?.displays = newDisplays
        }
    }

    private func enumerate() -> [DisplayInfo] {
        var result: [DisplayInfo] = []
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else {
            return result
        }

        let mainDisplayID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            let uuid = createStableDisplayFingerprint(for: id)
            let serial = getDisplaySerialNumber(for: id)
            let frame = CGDisplayBounds(id)
            let name = displayName(for: id)
            let isPrimary = id == mainDisplayID
            result.append(DisplayInfo(id: id, uuid: uuid, serialNumber: serial, frame: frame, name: name, isPrimary: isPrimary))
        }

        result.sort { d1, d2 in
            if d1.isPrimary && !d2.isPrimary { return true }
            if !d1.isPrimary && d2.isPrimary { return false }
            return d1.frame.minX < d2.frame.minX
        }

        return result
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? CGDirectDisplayID) == displayID
        }) {
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

    private func registerReconfigurationCallback() {
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in
            guard let userInfo = userInfo else { return }
            let service = Unmanaged<DisplayService>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                service.handleReconfiguration(displayID: displayID, flags: flags)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func handleReconfiguration(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.addFlag) {
            refresh()
            if let added = displays.first(where: { $0.id == displayID }) {
                onDisplayAdded?(added)
            }
        } else if flags.contains(.removeFlag) {
            refresh()
            onDisplayRemoved?(displayID)
        } else if flags.contains(.movedFlag) ||
                  flags.contains(.desktopShapeChangedFlag) ||
                  flags.contains(.enabledFlag) ||
                  flags.contains(.disabledFlag) ||
                  flags.contains(.setMainFlag) ||
                  flags.contains(.setModeFlag) {
            refresh()
            onLayoutChanged?()
        }
    }
}
