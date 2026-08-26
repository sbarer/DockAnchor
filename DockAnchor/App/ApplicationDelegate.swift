//
//  ApplicationDelegate.swift
//  DockAnchor
//

import Cocoa
import os.log

class ApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var appSettings: AppSettings { AppSettings.shared }
    private var coordinator: DockCoordinator { DockCoordinator.shared }
    private var menuBarManager: MenuBarManager { MenuBarManager.shared }
    private var updateChecker: UpdateChecker { UpdateChecker.shared }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DockAnchorDeluxe", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        logger.info("applicationDidFinishLaunching: PID=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) AXTrusted=\(AXIsProcessTrusted(), privacy: .public) runInBackground=\(self.appSettings.runInBackground, privacy: .public) autoRelocate=\(self.appSettings.autoRelocateDock, privacy: .public)")

        NotificationCenter.default.addObserver(
            self, selector: #selector(updateDockVisibility), name: .dockVisibilityChanged, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSystemWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSystemSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        menuBarManager.setup(appSettings: appSettings, coordinator: coordinator, updateChecker: updateChecker)
        updateActivationPolicy()

        guard PermissionService.shared.check() else {
            print("[AppDelegate] applicationDidFinishLaunching: AX permission not granted — skipping monitoring setup")
            return
        }
        coordinator.changeAnchorDisplay(toUUID: appSettings.selectedDisplayUUID)

        if appSettings.runInBackground {
            print("[AppDelegate] applicationDidFinishLaunching: scheduling startMonitoring in 1.0s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                print("[AppDelegate] startMonitoring: firing")
                self?.coordinator.startMonitoring()
            }
        } else {
            print("[AppDelegate] applicationDidFinishLaunching: runInBackground=false — monitoring NOT auto-started")
        }
        if appSettings.autoRelocateDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                print("[AppDelegate:autoRelocateDock] firing relocateDock")
                self?.coordinator.relocateDock()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.updateChecker.checkForUpdates()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        updateChecker.checkForUpdates()
        if flag { menuBarManager.showMainWindow(); return false }
        for window in NSApp.windows {
            guard window.level == .normal, window.frame.width > 100, window.frame.height > 100 else { continue }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate: called — clean exit path")
        coordinator.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleSystemSleep() {
        logger.info("handleSystemSleep: willSleepNotification received — stopping monitoring")
        coordinator.handleSystemSleep()
    }

    @objc private func handleSystemWake() {
        logger.info("handleSystemWake: didWakeNotification received — scheduling restart in 2s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.logger.info("handleSystemWake: 2s delay elapsed — calling coordinator.handleSystemWake")
            self?.coordinator.handleSystemWake()
        }
    }

    @objc private func updateDockVisibility() { updateActivationPolicy() }

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = appSettings.hideFromDock ? .accessory : .regular
        NSApp.setActivationPolicy(policy)
        DispatchQueue.main.async { [weak self] in
            if !(self?.appSettings.hideFromDock ?? false) { NSApp.activate(ignoringOtherApps: false) }
            self?.menuBarManager.ensureStatusBarVisible()
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name("com.apple.dock.refresh"), object: nil
            )
        }
    }
}
