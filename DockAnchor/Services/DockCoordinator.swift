//
//  DockCoordinator.swift
//  DockAnchor
//

import Foundation
import Cocoa
import Combine
import CoreGraphics

class DockCoordinator: ObservableObject {
    static let shared = DockCoordinator()

    // MARK: - Published
    @Published private(set) var isActive: Bool = false
    @Published private(set) var statusMessage: String = "Dock Anchor Deluxe Ready"
    @Published private(set) var anchoredDisplayName: String = "Primary"
    @Published private(set) var needsPermissionReset: Bool = false
    @Published private(set) var displays: [DisplayInfo] = []

    // MARK: - Internal state
    var anchorDisplayUUID: String = ""
    var dockPosition: DockPosition = .bottom
    private(set) var isDockAnchored: Bool = true

    private var positionCheckTimer: Timer?
    private var hotCornerWatchTimer: Timer?
    private var hotCornerAttempts: Int = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed
    var anchorDisplayID: CGDirectDisplayID {
        DisplayService.shared.displayID(forUUID: anchorDisplayUUID) ?? CGMainDisplayID()
    }

    private init() {
        setupInitialState()
        setupCallbacks()
        setupNotificationObservers()
    }

    // MARK: - Setup

    private func setupInitialState() {
        anchorDisplayUUID = AppSettings.shared.selectedDisplayUUID
        displays = DisplayService.shared.displays
        print("[DockCoordinator] setupInitialState: anchorDisplayUUID=\(anchorDisplayUUID) displays=\(displays.count) AXTrusted=\(AXIsProcessTrusted())")
        DisplayService.shared.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDisplays in
                self?.displays = newDisplays
                print("[DockCoordinator] displays updated: count=\(newDisplays.count) \(newDisplays.map { "\($0.name)[\($0.id)]" })")
            }
            .store(in: &cancellables)
        let systemPosition = DockResizeService.shared.currentPosition()
        if let profilePosition = AppSettings.shared.activeProfile?.dockPosition {
            dockPosition = profilePosition
            if systemPosition != profilePosition {
                print("[DockCoordinator] setupInitialState: system=\(systemPosition) differs from profile=\(profilePosition), using profile value")
            }
        } else {
            dockPosition = systemPosition
        }
        print("[DockCoordinator] setupInitialState: dockPosition=\(dockPosition)")
        updateAnchoredDisplayName()
        refreshAnchoredState()
        if !PermissionService.shared.check() {
            needsPermissionReset = true
            print("[DockCoordinator] setupInitialState: WARNING — AX permission not granted")
        }
    }

    private func setupCallbacks() {
        DisplayService.shared.onDisplayAdded = { [weak self] info in self?.handleDisplayAdded(info) }
        DisplayService.shared.onDisplayRemoved = { [weak self] id in self?.handleDisplayRemoved(id) }
        DisplayService.shared.onLayoutChanged = { [weak self] in self?.handleLayoutChanged() }
        MouseTrackingService.shared.onHotCornerDetected = { [weak self] in self?.startHotCornerWatch() }
        MouseTrackingService.shared.onStatusMessage = { [weak self] msg in
            DispatchQueue.main.async { self?.statusMessage = msg }
        }
        DockRelocationService.shared.onStatusMessage = { [weak self] msg in
            DispatchQueue.main.async { self?.statusMessage = msg }
        }
        DockRelocationService.shared.onRelocationComplete = { [weak self] in self?.refreshAnchoredState() }
        PermissionService.shared.onRevoked = { [weak self] in self?.handlePermissionRevoked() }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .anchorDisplayChanged)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uuid in self?.changeAnchorDisplay(toUUID: uuid) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .defaultAnchorDisplayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if AppSettings.shared.activeProfileID == nil {
                    self.applyDefaultAnchorIfNeeded()
                }
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().publisher(
            for: NSNotification.Name("com.apple.dock.refresh")
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            // Physical detection is most accurate; fall back to active profile, then defaults
            if let detected = DockRelocationService.shared.detectDockState()?.position {
                if self.dockPosition != detected {
                    print("[DockCoordinator] dock.refresh: dockPosition → \(detected) (visibleFrame)")
                    self.dockPosition = detected
                }
            } else if let profilePos = AppSettings.shared.activeProfile?.dockPosition {
                if self.dockPosition != profilePos {
                    print("[DockCoordinator] dock.refresh: dockPosition → \(profilePos) (profile, stale defaults ignored)")
                    self.dockPosition = profilePos
                }
            } else {
                let fresh = DockResizeService.shared.currentPosition()
                if self.dockPosition != fresh {
                    print("[DockCoordinator] dock.refresh: dockPosition → \(fresh) (defaults)")
                    self.dockPosition = fresh
                }
            }
            self.refreshAnchoredState()
        }
        .store(in: &cancellables)
    }

    // MARK: - Monitoring lifecycle

    func startMonitoring() {
        print("[DockCoordinator] startMonitoring: called — isActive=\(isActive) AXTrusted=\(AXIsProcessTrusted()) anchorUUID=\(anchorDisplayUUID) anchorID=\(anchorDisplayID)")
        guard PermissionService.shared.check() else {
            needsPermissionReset = true
            statusMessage = "Accessibility permissions required"
            print("[DockCoordinator] startMonitoring: FAILED — no AX permission")
            return
        }
        guard !isActive else {
            print("[DockCoordinator] startMonitoring: already active, skipping")
            return
        }
        guard MouseTrackingService.shared.startTracking() else {
            needsPermissionReset = true
            print("[DockCoordinator] startMonitoring: FAILED — startTracking returned false")
            return
        }
        PermissionService.shared.startPolling(interval: 5.0)
        startPositionCheckTimer()
        isActive = true
        statusMessage = "Dock Anchor Deluxe Active - Monitoring mouse movement"
        print("[DockCoordinator] startMonitoring: SUCCESS — isActive=true")
    }

    func stopMonitoring() {
        print("[DockCoordinator] stopMonitoring: called")
        PermissionService.shared.stopPolling()
        stopPositionCheckTimer()
        MouseTrackingService.shared.stopTracking()
        isActive = false
        statusMessage = "Dock Anchor Deluxe Stopped"
    }

    // MARK: - Anchor display

    func changeAnchorDisplay(toUUID uuid: String) {
        print("[DockCoordinator] changeAnchorDisplay: uuid=\(uuid) available=\(DisplayService.shared.isAvailable(uuid: uuid))")
        if DisplayService.shared.isAvailable(uuid: uuid) {
            anchorDisplayUUID = uuid
            updateAnchoredDisplayName()
            print("[DockCoordinator] changeAnchorDisplay: set anchorDisplayUUID=\(anchorDisplayUUID) anchorID=\(anchorDisplayID) name=\(anchoredDisplayName)")
            postStatus("Anchor changed to \(anchoredDisplayName)")
        } else {
            let defaultUUID = defaultAnchorDisplayUUID()
            anchorDisplayUUID = defaultUUID
            updateAnchoredDisplayName()
            let defaultName = AppSettings.shared.defaultAnchorDisplay == .builtIn ? "Built-in" : "Primary"
            postStatus("Requested display not available - using \(defaultName)")
            NotificationCenter.default.post(name: .anchorDisplayChanged, object: defaultUUID)
        }
    }

    func changeAnchorDisplay(to displayID: CGDirectDisplayID) {
        guard let uuid = DisplayService.shared.uuid(forDisplayID: displayID) else { return }
        changeAnchorDisplay(toUUID: uuid)
    }

    func applyDefaultAnchorIfNeeded() {
        let defaultUUID = defaultAnchorDisplayUUID()
        guard anchorDisplayUUID != defaultUUID else { return }
        anchorDisplayUUID = defaultUUID
        updateAnchoredDisplayName()
        AppSettings.shared.selectedDisplayUUID = defaultUUID
    }

    // MARK: - Dock operations

    func relocateDock() {
        guard let anchorDisplay = DisplayService.shared.display(forUUID: anchorDisplayUUID) else {
            statusMessage = "Cannot relocate dock - anchor display not found"
            return
        }
        let pos = dockPosition
        Task { await DockRelocationService.shared.relocate(to: anchorDisplay, dockPosition: pos) }
    }

    func applyDockSettings(position: DockPosition?, tileSize: Int?) {
        guard position != nil || tileSize != nil else { return }
        if let position {
            Task { await DockResizeService.shared.setPosition(position) }
            self.dockPosition = position
            // Dock process restarts after a position change — delay relocation to let it settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.relocateDock()
            }
        }
        if let tileSize {
            Task { await DockResizeService.shared.setTileSize(tileSize) }
        }
    }

    // MARK: - Display event handlers

    func handleDisplayAdded(_ info: DisplayInfo) {
        updateAnchoredDisplayName()
        let profileActivated = activateProfileIfNeeded(for: info.uuid)
        if !profileActivated {
            handleDisplayAddedNoProfile(info: info)
        }
        postStatus(isActive ? "Dock Anchor Deluxe Active - Monitoring mouse movement" : "Dock Anchor Deluxe Ready")
    }

    private func activateProfileIfNeeded(for uuid: String) -> Bool {
        guard let profile = AppSettings.shared.findAutoActivateProfile(forDisplayUUID: uuid) else {
            return false
        }
        let alreadyActive = AppSettings.shared.activeProfileID == profile.id
        let anchorMatches = AppSettings.shared.selectedDisplayUUID == profile.anchorDisplayUUID
        if !alreadyActive || !anchorMatches {
            AppSettings.shared.switchToProfile(profile)
            statusMessage = "Auto-activated profile: \(profile.name)"
            return true
        }
        return false
    }

    private func handleDisplayAddedNoProfile(info: DisplayInfo) {
        if AppSettings.shared.activeProfileID == nil && AppSettings.shared.defaultAnchorDisplay == .main {
            let mainUUID = mainDisplayUUID()
            if anchorDisplayUUID != mainUUID {
                anchorDisplayUUID = mainUUID
                AppSettings.shared.selectedDisplayUUID = mainUUID
                updateAnchoredDisplayName()
                statusMessage = "Main display changed - anchoring to \(anchoredDisplayName)"
            }
        } else {
            restorePreferredAnchorIfAvailable()
        }
        if AppSettings.shared.autoRelocateDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.relocateDock()
            }
        }
    }

    private func restorePreferredAnchorIfAvailable() {
        let preferred = AppSettings.shared.selectedDisplayUUID
        guard DisplayService.shared.isAvailable(uuid: preferred),
              let canonical = DisplayService.shared.canonicalUUID(matching: preferred),
              anchorDisplayUUID != canonical else { return }
        anchorDisplayUUID = canonical
        updateAnchoredDisplayName()
        statusMessage = "Preferred display reconnected - restoring anchor to \(anchoredDisplayName)"
        if canonical != preferred {
            AppSettings.shared.selectedDisplayUUID = canonical
        }
    }

    func handleDisplayRemoved(_ id: CGDirectDisplayID) {
        let anchorGone = !DisplayService.shared.displays.contains { $0.uuid == anchorDisplayUUID }
        guard anchorGone else { return }
        anchorDisplayUUID = defaultAnchorDisplayUUID()
        updateAnchoredDisplayName()
        let defaultName = AppSettings.shared.defaultAnchorDisplay == .builtIn ? "Built-in" : "Primary"
        statusMessage = "Anchor display disconnected - temporarily using \(defaultName)"
    }

    func handleLayoutChanged() {
        updateAnchoredDisplayName()
        applyMainAnchorIfNeeded()
    }

    private func applyMainAnchorIfNeeded() {
        guard AppSettings.shared.activeProfileID == nil,
              AppSettings.shared.defaultAnchorDisplay == .main else { return }
        let mainUUID = mainDisplayUUID()
        guard anchorDisplayUUID != mainUUID else { return }
        anchorDisplayUUID = mainUUID
        AppSettings.shared.selectedDisplayUUID = mainUUID
        updateAnchoredDisplayName()
        statusMessage = "Main display changed - anchoring to \(anchoredDisplayName)"
        if AppSettings.shared.autoRelocateDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.relocateDock()
            }
        }
        postStatus(isActive ? "Dock Anchor Deluxe Active - Monitoring mouse movement" : "Dock Anchor Deluxe Ready")
    }

    // MARK: - Permission

    func handlePermissionRevoked() {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Accessibility permissions revoked - stopping monitoring"
            self?.stopMonitoring()
        }
    }

    // MARK: - Display name

    func updateAnchoredDisplayName() {
        anchoredDisplayName = DisplayService.shared.display(forUUID: anchorDisplayUUID)?.name ?? "Unknown"
    }

    // MARK: - Timers

    func startPositionCheckTimer() {
        guard positionCheckTimer == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.positionCheckTimer == nil else { return }
            self.positionCheckTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.runPositionCheck()
            }
        }
    }

    func stopPositionCheckTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.positionCheckTimer?.invalidate()
            self?.positionCheckTimer = nil
        }
    }

    private func runPositionCheck() {
        guard AppSettings.shared.autoRelocateDock else { return }
        guard !DockRelocationService.shared.isRelocating else { return }
        guard let anchorDisplay = DisplayService.shared.display(forUUID: anchorDisplayUUID) else { return }
        guard !DockRelocationService.shared.isDockOnDisplay(anchorDisplay, dockPosition: dockPosition) else { return }
        print("[DockCoordinator] positionCheck: dock not on anchor display, relocating")
        relocateDock()
    }

    func startHotCornerWatch() {
        stopHotCornerWatch()
        hotCornerAttempts = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.scheduleHotCornerTick()
        }
    }

    func stopHotCornerWatch() {
        hotCornerWatchTimer?.invalidate()
        hotCornerWatchTimer = nil
        hotCornerAttempts = 0
    }

    private func scheduleHotCornerTick() {
        guard hotCornerWatchTimer == nil else { return }
        hotCornerWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.hotCornerTick()
        }
    }

    private func hotCornerTick() {
        guard let anchorDisplay = DisplayService.shared.display(forUUID: anchorDisplayUUID) else {
            stopHotCornerWatch()
            return
        }
        if DockRelocationService.shared.isDockOnDisplay(anchorDisplay, dockPosition: dockPosition) {
            stopHotCornerWatch()
            return
        }
        hotCornerAttempts += 1
        if hotCornerAttempts > 5 {
            stopHotCornerWatch()
            return
        }
        guard !DockRelocationService.shared.isRelocating else { return }
        relocateDock()
    }

    // MARK: - Helpers

    func refreshAnchoredState() {
        guard let anchorDisplay = DisplayService.shared.display(forUUID: anchorDisplayUUID) else {
            return // can't verify, keep current isDockAnchored
        }
        guard let state = DockRelocationService.shared.detectDockState() else {
            return // autohide or transitioning — keep current isDockAnchored rather than defaulting to false
        }
        if dockPosition != state.position {
            print("[DockCoordinator] refreshAnchoredState: correcting dockPosition \(dockPosition) → \(state.position)")
            dockPosition = state.position
        }
        isDockAnchored = state.displayID == anchorDisplay.id
    }

    func defaultAnchorDisplayUUID() -> String {
        switch AppSettings.shared.defaultAnchorDisplay {
        case .builtIn:
            return builtInDisplayUUID() ?? mainDisplayUUID()
        case .main:
            return mainDisplayUUID()
        }
    }

    func builtInDisplayUUID() -> String? {
        DisplayService.shared.displays.first { $0.name.contains("Built-in") }?.uuid
    }

    func mainDisplayUUID() -> String {
        DisplayService.fingerprint(for: CGMainDisplayID())
    }

    func postStatus(_ message: String, resetAfter: Double = 3.0) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + resetAfter) { [weak self] in
                guard let self else { return }
                self.statusMessage = self.isActive
                    ? "Dock Anchor Deluxe Active - Monitoring mouse movement"
                    : "Dock Anchor Deluxe Ready"
            }
        }
    }
}
