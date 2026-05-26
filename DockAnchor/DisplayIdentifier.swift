//
//  DisplayIdentifier.swift
//  DockAnchor
//

import Foundation
import Cocoa
import CoreGraphics
import IOKit

// MARK: - EDID Serial Number Extraction

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

// MARK: - DockMonitor Display Identification

extension DockMonitor {

    static func getDisplayUUID(for displayID: CGDirectDisplayID) -> String {
        return createStableDisplayFingerprint(for: displayID)
    }

    static func getSerialNumber(for displayID: CGDirectDisplayID) -> UInt32? {
        return getDisplaySerialNumber(for: displayID)
    }

    func getDisplayID(forUUID uuid: String) -> CGDirectDisplayID? {
        if let exactMatch = availableDisplays.first(where: { $0.uuid == uuid }) {
            return exactMatch.id
        }
        let baseUUID = extractBaseUUID(from: uuid)
        return availableDisplays.first { extractBaseUUID(from: $0.uuid) == baseUUID }?.id
    }

    func getDisplayUUID(forID displayID: CGDirectDisplayID) -> String? {
        return availableDisplays.first { $0.id == displayID }?.uuid
    }

    func isDisplayAvailable(uuid: String) -> Bool {
        if availableDisplays.contains(where: { $0.uuid == uuid }) {
            return true
        }
        let baseUUID = extractBaseUUID(from: uuid)
        return availableDisplays.contains { extractBaseUUID(from: $0.uuid) == baseUUID }
    }

    func getCurrentUUID(matching uuid: String) -> String? {
        if let exactMatch = availableDisplays.first(where: { $0.uuid == uuid }) {
            return exactMatch.uuid
        }
        let baseUUID = extractBaseUUID(from: uuid)
        return availableDisplays.first { extractBaseUUID(from: $0.uuid) == baseUUID }?.uuid
    }

    // fileprivate so DisplayManager extensions in other files can call it via isDisplayAvailable/getCurrentUUID
    func extractBaseUUID(from fingerprint: String) -> String {
        if let snRange = fingerprint.range(of: "-SN") {
            return String(fingerprint[..<snRange.lowerBound])
        }
        if let vRange = fingerprint.range(of: "-V") {
            return String(fingerprint[..<vRange.lowerBound])
        }
        return fingerprint
    }

    func getBuiltInDisplayUUID() -> String? {
        return availableDisplays.first { $0.name.contains("Built-in") }?.uuid
    }

    func getMainDisplayUUID() -> String {
        return Self.getDisplayUUID(for: CGMainDisplayID())
    }

    func getDefaultAnchorDisplayUUID() -> String {
        switch AppSettings.shared.defaultAnchorDisplay {
        case .builtIn:
            return getBuiltInDisplayUUID() ?? getMainDisplayUUID()
        case .main:
            return getMainDisplayUUID()
        }
    }
}
