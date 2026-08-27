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
        return false
    }
}
