//
//  DockResizeService.swift
//  DockAnchor
//

import Foundation
import Cocoa

class DockResizeService {
    static let shared = DockResizeService()
    private init() {}

    // MARK: - Public API

    func setPosition(_ position: DockPosition) async {
        let source = """
        tell application "System Events" to tell dock preferences
            set screen edge to \(position.rawValue)
        end tell
        """
        await MainActor.run {
            runAppleScript(source)
        }
    }

    func setTileSize(_ pixels: Int) async {
        let percentage = Double(pixels) / 100.0
        let source = """
        tell application "System Events"
            tell dock preferences
                set dock size to \(percentage)
            end tell
        end tell
        """
        await MainActor.run {
            runAppleScript(source)
        }
    }

    func currentPosition() -> DockPosition {
        let raw = readDefaults(key: "orientation")
        return parsePosition(raw)
    }

    func currentTileSize() -> Int {
        let raw = readDefaults(key: "tilesize")
        return parseTileSize(raw)
    }

    // MARK: - Internal (testable)

    func parsePosition(_ raw: String) -> DockPosition {
        switch raw.lowercased() {
        case "left":   return .left
        case "right":  return .right
        case "bottom": return .bottom
        default:       return .bottom
        }
    }

    func parseTileSize(_ raw: String) -> Int {
        return Int(raw) ?? 48
    }

    // MARK: - Private

    private func runAppleScript(_ source: String) {
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo = errorInfo {
            print("[DockResizeService] AppleScript error: \(errorInfo)")
        }
    }

    private func readDefaults(key: String) -> String {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.dock", key]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
