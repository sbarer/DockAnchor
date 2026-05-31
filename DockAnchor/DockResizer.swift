//
//  DockResizer.swift
//  DockAnchor
//
//  Created by Simon Barer on 31/5/2026.
//

import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics

let MAX_SIZE = 60

extension DockMonitor {
    func changeDockSize(to pixelSize: Int) {
        let percentageSize = Double(pixelSize) / Double(100)
        let source = """
        tell application "System Events"
            tell dock preferences
                set dock size to \(percentageSize)
            end tell
        end tell
        """
        print("[DockResizer] changeDockSize: \(percentageSize)")

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                let script = NSAppleScript(source: source)
                var errorInfo: NSDictionary?
                script?.executeAndReturnError(&errorInfo)
                if let errorInfo = errorInfo {
                    print("[DockSettings] changeDockSize error: \(errorInfo)")
                } else {
                    print("[DockSettings] changeDockSize applied: \(pixelSize)px")
                }
            }
        }
    }

    /// Reads the current dock tile size via `defaults read`. Blocks the calling thread briefly.
    static func readCurrentDockTileSize() -> Int {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.dock", "tilesize"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("[DockResizer] currentDockSize: \(str)")
            return Int(str) ?? 48
        } catch {
            return 48
        }
    }
}
