//
//  MenuBarManager.swift
//  DockAnchor
//

import Cocoa
import Combine

class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var appSettings: AppSettings?
    private var coordinator: DockCoordinator?
    private var updateChecker: UpdateChecker?
    private var cancellables = Set<AnyCancellable>()

    deinit {
        removeStatusBar()
        cancellables.removeAll()
    }

    func setup(appSettings: AppSettings, coordinator: DockCoordinator, updateChecker: UpdateChecker) {
        self.appSettings = appSettings
        self.coordinator = coordinator
        self.updateChecker = updateChecker

        if appSettings.showStatusIcon { setupStatusBar() }

        appSettings.$showStatusIcon.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] showIcon in
            if showIcon { self?.setupStatusBar() } else { self?.removeStatusBar() }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDisplaysChanged), name: .displaysDidChange, object: nil
        )
    }

    @objc private func handleDisplaysChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateDisplaySubmenu() }
    }

    private func setupStatusBar() {
        removeStatusBar()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockAnchor")
            button.toolTip = "DockAnchor - Click to open"
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        setupStatusMenu()
    }

    private func removeStatusBar() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
    }

    private func setupStatusMenu() {
        guard let coordinator = coordinator, let appSettings = appSettings else { return }

        let menu = NSMenu()
        let statusMenuItem = NSMenuItem()
        updateStatusMenuItem(statusMenuItem, isActive: coordinator.isActive)
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let anchorMenuItem = NSMenuItem()
        anchorMenuItem.title = "📍 \(coordinator.anchoredDisplayName)"
        anchorMenuItem.isEnabled = false
        menu.addItem(anchorMenuItem)

        menu.addItem(.separator())

        let toggleMenuItem = NSMenuItem(title: coordinator.isActive ? "Stop Protection" : "Start Protection", action: #selector(toggleProtection), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())
        menu.addItem(buildDisplayMenuItem(coordinator: coordinator, appSettings: appSettings))
        menu.addItem(buildThemeMenuItem(appSettings: appSettings))
        menu.addItem(buildProfilesMenuItem(appSettings: appSettings))
        menu.addItem(.separator())
        addUtilityItems(to: menu)

        statusItem?.menu = menu
        bindPublishers(statusMenuItem: statusMenuItem, toggleMenuItem: toggleMenuItem, anchorMenuItem: anchorMenuItem, coordinator: coordinator, appSettings: appSettings)
    }

    private func buildDisplayMenuItem(coordinator: DockCoordinator, appSettings: AppSettings) -> NSMenuItem {
        let submenu = NSMenu()
        for display in coordinator.displays {
            let item = NSMenuItem(title: display.name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.uuid
            item.state = display.uuid == appSettings.selectedDisplayUUID ? .on : .off
            submenu.addItem(item)
        }
        let menuItem = NSMenuItem(title: "Anchor to Display", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private func buildThemeMenuItem(appSettings: AppSettings) -> NSMenuItem {
        let submenu = NSMenu()
        for theme in AppTheme.allCases {
            let item = NSMenuItem(title: theme.rawValue, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme
            item.state = theme == appSettings.appTheme ? .on : .off
            submenu.addItem(item)
        }
        let menuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private func buildProfilesMenuItem(appSettings: AppSettings) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        menuItem.submenu = buildProfilesSubmenuContent(appSettings: appSettings)
        return menuItem
    }

    private func buildProfilesSubmenuContent(appSettings: AppSettings) -> NSMenu {
        let submenu = NSMenu()
        guard !appSettings.profiles.isEmpty else {
            let empty = NSMenuItem(title: "No Profiles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }
        for profile in appSettings.profiles {
            let title = profile.autoActivate ? "⚡ \(profile.name)" : profile.name
            let item = NSMenuItem(title: title, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == appSettings.activeProfileID ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func addUtilityItems(to menu: NSMenu) {
        let updateItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let feedbackItem = NSMenuItem(title: "Feedback & Issues", action: #selector(openFeedback), keyEquivalent: "")
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        let showItem = NSMenuItem(title: "Show DockAnchor", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DockAnchor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func bindPublishers(statusMenuItem: NSMenuItem, toggleMenuItem: NSMenuItem, anchorMenuItem: NSMenuItem, coordinator: DockCoordinator, appSettings: AppSettings) {
        coordinator.$isActive.receive(on: DispatchQueue.main).sink { [weak self] isActive in
            self?.updateStatusMenuItem(statusMenuItem, isActive: isActive)
            toggleMenuItem.title = isActive ? "Stop Protection" : "Start Protection"
        }.store(in: &cancellables)

        coordinator.$anchoredDisplayName.receive(on: DispatchQueue.main).sink { [weak self] name in
            anchorMenuItem.title = "📍 \(name)"
            self?.refreshDisplaySubmenu()
        }.store(in: &cancellables)

        coordinator.$statusMessage.receive(on: DispatchQueue.main).sink { [weak self] msg in
            self?.statusItem?.button?.toolTip = "DockAnchor - \(msg)"
        }.store(in: &cancellables)

        coordinator.$displays.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateDisplaySubmenu()
        }.store(in: &cancellables)

        appSettings.$profiles.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshProfilesSubmenu()
        }.store(in: &cancellables)

        appSettings.$activeProfileID.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshProfilesSubmenu()
        }.store(in: &cancellables)
    }

    private func updateStatusMenuItem(_ item: NSMenuItem, isActive: Bool) {
        item.title = isActive ? "🟢 Protection Active" : "🔴 Protection Inactive"
    }

    private func refreshDisplaySubmenu() {
        guard let menu = statusItem?.menu,
              let displayMenuItem = menu.item(withTitle: "Anchor to Display"),
              let submenu = displayMenuItem.submenu else { return }
        for item in submenu.items {
            if let uuid = item.representedObject as? String {
                item.state = uuid == appSettings?.selectedDisplayUUID ? .on : .off
            }
        }
    }

    private func updateDisplaySubmenu() {
        guard let menu = statusItem?.menu,
              let displayMenuItem = menu.item(withTitle: "Anchor to Display"),
              let coordinator = coordinator,
              let appSettings = appSettings else { return }
        let newSubmenu = NSMenu()
        for display in coordinator.displays {
            let item = NSMenuItem(title: display.name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.uuid
            item.state = display.uuid == appSettings.selectedDisplayUUID ? .on : .off
            newSubmenu.addItem(item)
        }
        displayMenuItem.submenu = newSubmenu
    }

    private func refreshProfilesSubmenu() {
        guard let menu = statusItem?.menu,
              let profilesMenuItem = menu.item(withTitle: "Profiles"),
              let appSettings = appSettings else { return }
        profilesMenuItem.submenu = buildProfilesSubmenuContent(appSettings: appSettings)
    }

    private func refreshThemeSubmenu() {
        guard let menu = statusItem?.menu,
              let themeMenuItem = menu.item(withTitle: "Theme"),
              let submenu = themeMenuItem.submenu else { return }
        for item in submenu.items {
            if let theme = item.representedObject as? AppTheme {
                item.state = theme == appSettings?.appTheme ? .on : .off
            }
        }
    }

    @objc private func statusItemClicked() { showMainWindow() }

    @objc private func toggleProtection() {
        guard let coordinator = coordinator else { return }
        if coordinator.isActive { coordinator.stopMonitoring() } else { coordinator.startMonitoring() }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        appSettings?.selectedDisplayUUID = uuid
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? AppTheme else { return }
        appSettings?.appTheme = theme
        refreshThemeSubmenu()
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let profile = appSettings?.profiles.first(where: { $0.id == id }) else { return }
        appSettings?.switchToProfile(profile)
        refreshProfilesSubmenu()
    }

    @objc private func checkForUpdates() { updateChecker?.checkForUpdates(isManual: true) }

    @objc private func openFeedback() {
        if let url = URL(string: "https://github.com/bwya77/DockAnchor") { NSWorkspace.shared.open(url) }
    }

    @objc func showMainWindow() {
        if !(appSettings?.hideFromDock ?? false) { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        DistributedNotificationCenter.default().post(name: NSNotification.Name("com.apple.dock.refresh"), object: nil)

        for window in NSApp.windows where window.level == .normal && window.frame.width > 100 && window.frame.height > 100 {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.level == .normal && window.frame.width > 100 {
                window.makeKeyAndOrderFront(nil); break
            }
        }
    }

    @objc private func quitApp() { coordinator?.stopMonitoring(); NSApp.terminate(nil) }

    func ensureStatusBarVisible() {
        if statusItem == nil && (appSettings?.showStatusIcon ?? true) { setupStatusBar() }
    }
}
