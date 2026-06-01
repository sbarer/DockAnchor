//
//  ApplicationDelegate.swift
//  DockAnchor
//

import Cocoa

class ApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var appSettings: AppSettings { AppSettings.shared }
    private var coordinator: DockCoordinator { DockCoordinator.shared }
    private var menuBarManager: MenuBarManager { MenuBarManager.shared }
    private var updateChecker: UpdateChecker { UpdateChecker.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NotificationCenter.default.addObserver(
            self, selector: #selector(updateDockVisibility), name: .dockVisibilityChanged, object: nil
        )
        menuBarManager.setup(appSettings: appSettings, coordinator: coordinator, updateChecker: updateChecker)
        updateActivationPolicy()

        guard PermissionService.shared.check() else { return }
        coordinator.changeAnchorDisplay(toUUID: appSettings.selectedDisplayUUID)

        if appSettings.runInBackground {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.coordinator.startMonitoring()
            }
        }
        if appSettings.autoRelocateDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
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
        coordinator.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
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
