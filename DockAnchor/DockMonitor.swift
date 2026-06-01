//
//  DockMonitor.swift
//  DockAnchor
//
//  Stub — logic moved to Services/DockCoordinator.swift and associated service singletons.
//  Kept as empty class so existing extension files still compile during the refactor.
//

import Foundation
import Cocoa
import ApplicationServices
import Carbon
import CoreGraphics
import Combine
import IOKit

class DockMonitor: NSObject, ObservableObject {
    static let shared = DockMonitor()

    @Published var isActive = false
    @Published var anchoredDisplay: String = "Primary"
    @Published var statusMessage = "Dock Anchor Ready"
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var needsPermissionReset = false

    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var isMonitoring = false
    var anchorDisplayUUID: String = ""
    var dockPosition: DockPosition = .bottom
    private var cancellables = Set<AnyCancellable>()
    var permissionCheckTimer: Timer?
    var hotCornerWatchTimer: Timer?
    var positionCheckTimer: Timer?

    var anchorDisplayID: CGDirectDisplayID {
        return availableDisplays.first { $0.uuid == anchorDisplayUUID }?.id ?? CGMainDisplayID()
    }

    var isRelocating = false
    let cornerZoneSize: CGFloat = 5
    let syntheticEventMarker: Int64 = 0xD0C4A5C4

    override init() {
        super.init()
        // No-op: app now uses DockCoordinator.shared as the entry point
    }
}
