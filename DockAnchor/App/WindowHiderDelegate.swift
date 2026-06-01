//
//  WindowHiderDelegate.swift
//  DockAnchor
//

import Cocoa

class WindowHiderDelegate: NSObject, NSWindowDelegate {
    private var appSettings: AppSettings?

    func setup(appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if appSettings?.hideFromDock == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
                DistributedNotificationCenter.default().post(
                    name: NSNotification.Name("com.apple.dock.refresh"),
                    object: nil
                )
            }
        }
        return false
    }
}
