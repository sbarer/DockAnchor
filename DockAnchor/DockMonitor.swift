//
//  DockMonitor.swift
//  DockAnchor
//
//  Created by Bradley Wyatt on 7/2/25.
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
    var anchorDisplayUUID: String = ""  // Hardware UUID for stable anchor tracking
    var dockPosition: DockPosition = .bottom
    private var cancellables = Set<AnyCancellable>()
    var permissionCheckTimer: Timer?
    var hotCornerWatchTimer: Timer?

    var anchorDisplayID: CGDirectDisplayID {
        return availableDisplays.first { $0.uuid == anchorDisplayUUID }?.id ?? CGMainDisplayID()
    }

    var isRelocating = false
    let cornerZoneSize: CGFloat = 5
    let syntheticEventMarker: Int64 = 0xD0C4A5C4 // "DOCKASCR" in hex-ish

    override init() {
        super.init()
        setupInitialState()
        setupNotificationObservers()
    }

    private func setupInitialState() {
        anchorDisplayUUID = Self.getDisplayUUID(for: CGMainDisplayID())
        updateAvailableDisplays()
        detectCurrentDockPosition()
        setupDisplayConfigurationMonitoring()
        _ = requestAccessibilityPermissions()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .anchorDisplayChanged)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDisplayUUID in
                self?.changeAnchorDisplay(toUUID: newDisplayUUID)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .defaultAnchorDisplayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if AppSettings.shared.activeProfileID == nil {
                    self.applyDefaultAnchorIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func applyDefaultAnchorIfNeeded() {
        let defaultUUID = getDefaultAnchorDisplayUUID()
        if anchorDisplayUUID != defaultUUID {
            anchorDisplayUUID = defaultUUID
            updateAnchoredDisplayName()
            AppSettings.shared.selectedDisplayUUID = defaultUUID
        }
    }

    func changeAnchorDisplay(toUUID uuid: String) {
        let isDisplayAvailable = availableDisplays.contains { $0.uuid == uuid }

        if isDisplayAvailable {
            anchorDisplayUUID = uuid
            updateAnchoredDisplayName()
            statusMessage = "Anchor changed to \(anchoredDisplay)"
        } else {
            let defaultUUID = getDefaultAnchorDisplayUUID()
            anchorDisplayUUID = defaultUUID
            updateAnchoredDisplayName()
            let defaultName = AppSettings.shared.defaultAnchorDisplay == .builtIn ? "Built-in" : "Primary"
            statusMessage = "Requested display not available - using \(defaultName)"
            NotificationCenter.default.post(name: .anchorDisplayChanged, object: defaultUUID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.statusMessage = self.isActive ? "Dock Anchor Active - Monitoring mouse movement" : "Dock Anchor Ready"
        }
    }

    func changeAnchorDisplay(to displayID: CGDirectDisplayID) {
        let uuid = Self.getDisplayUUID(for: displayID)
        changeAnchorDisplay(toUUID: uuid)
    }

    func applyDockSettings(position: DockPosition?, tileSize: Int?) {
        guard position != nil || tileSize != nil else { return }
        if let position = position { changeDockPosition(to: position) }
        if let size = tileSize { changeDockSize(to: size) }
    }

    deinit {
        if Thread.isMainThread {
            stopMonitoring()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.stopMonitoring()
            }
        }

        CGDisplayRemoveReconfigurationCallback({ (displayID, flags, userInfo) in
            guard let userInfo = userInfo else { return }
            let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleDisplayConfigurationChange(displayID: displayID, flags: flags)
        }, Unmanaged.passUnretained(self).toOpaque())

        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
