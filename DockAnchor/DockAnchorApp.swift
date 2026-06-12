//
//  DockAnchorApp.swift
//  DockAnchor
//

import SwiftUI
import Cocoa

@main
struct DockAnchorApp: App {
    let persistenceController = PersistenceController.shared

    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var coordinator = DockCoordinator.shared
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var appDelegate
    private let windowHiderDelegate = WindowHiderDelegate()

    var body: some Scene {
        WindowGroup("Dock Anchor Deluxe") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appSettings)
                .environmentObject(coordinator)
                .environmentObject(updateChecker)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
                .onAppear {
                    windowHiderDelegate.setup(appSettings: appSettings)
                }
                .background(WindowAccessor { window in
                    window?.delegate = windowHiderDelegate
                })
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Dock Anchor Deluxe") { menuBarManager.showMainWindow() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Divider()
                Button(coordinator.isActive ? "Stop Protection" : "Start Protection") {
                    if coordinator.isActive { coordinator.stopMonitoring() }
                    else { coordinator.startMonitoring() }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}
