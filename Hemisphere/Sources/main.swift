import AppKit
import SwiftUI

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser.path + "/hemisphere.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(logMessage.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: logMessage.data(using: .utf8), attributes: nil)
    }
}

@main
struct HemisphereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty - we use menu bar only
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var wallpaperManager: WallpaperManager?

    // Menu items
    var lastUpdatedMenuItem: NSMenuItem?
    var satelliteMenuItem: NSMenuItem?
    var darkMenuItem: NSMenuItem?
    var lightMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cloud.sun.rain", accessibilityDescription: "Hemisphere")
        }

        // Create menu
        let menu = NSMenu()

        lastUpdatedMenuItem = NSMenuItem(title: "Last updated: --", action: nil, keyEquivalent: "")
        lastUpdatedMenuItem?.isEnabled = false
        menu.addItem(lastUpdatedMenuItem!)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Refresh Wallpaper", action: #selector(refreshWallpaper), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())

        let mapStyleMenu = NSMenu()

        satelliteMenuItem = NSMenuItem(title: "Satellite", action: #selector(setMapStyleSatellite), keyEquivalent: "")
        satelliteMenuItem?.state = .on  // Default selected
        mapStyleMenu.addItem(satelliteMenuItem!)

        darkMenuItem = NSMenuItem(title: "Dark", action: #selector(setMapStyleDark), keyEquivalent: "")
        mapStyleMenu.addItem(darkMenuItem!)

        lightMenuItem = NSMenuItem(title: "Light", action: #selector(setMapStyleLight), keyEquivalent: "")
        mapStyleMenu.addItem(lightMenuItem!)

        let mapStyleItem = NSMenuItem(title: "Map Style", action: nil, keyEquivalent: "")
        mapStyleItem.submenu = mapStyleMenu
        menu.addItem(mapStyleItem)

        menu.addItem(NSMenuItem.separator())

        let autoRefreshItem = NSMenuItem(title: "Auto-Refresh (10 min)", action: #selector(toggleAutoRefresh), keyEquivalent: "")
        autoRefreshItem.state = .on
        menu.addItem(autoRefreshItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu

        // Initialize wallpaper manager
        wallpaperManager = WallpaperManager()
        wallpaperManager?.onWallpaperSet = { [weak self] in
            self?.updateLastUpdatedTime()
        }
        wallpaperManager?.startListening()

        // Initial wallpaper set
        refreshWallpaper()
    }

    func updateLastUpdatedTime() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: Date())
        lastUpdatedMenuItem?.title = "Last updated: \(timeString)"
    }

    @objc func refreshWallpaper() {
        wallpaperManager?.generateAndSetWallpaper()
    }

    @objc func setMapStyleSatellite() {
        wallpaperManager?.mapStyle = .satellite
        updateStyleCheckmarks()
        refreshWallpaper()
    }

    @objc func setMapStyleDark() {
        wallpaperManager?.mapStyle = .dark
        updateStyleCheckmarks()
        refreshWallpaper()
    }

    @objc func setMapStyleLight() {
        wallpaperManager?.mapStyle = .light
        updateStyleCheckmarks()
        refreshWallpaper()
    }

    func updateStyleCheckmarks() {
        satelliteMenuItem?.state = wallpaperManager?.mapStyle == .satellite ? .on : .off
        darkMenuItem?.state = wallpaperManager?.mapStyle == .dark ? .on : .off
        lightMenuItem?.state = wallpaperManager?.mapStyle == .light ? .on : .off
    }

    @objc func toggleAutoRefresh(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        wallpaperManager?.autoRefreshEnabled = sender.state == .on
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

enum MapStyle: String {
    case satellite = "satellite"
    case dark = "dark"
    case light = "light"
}

class WallpaperManager {
    var mapStyle: MapStyle = .satellite
    var autoRefreshEnabled = true
    var onWallpaperSet: (() -> Void)?  // Callback when wallpaper is updated
    private var refreshTimer: Timer?
    private var isGenerating = false  // Prevent concurrent generations

    init() {
        // Start auto-refresh timer
        startAutoRefresh()
    }

    func startListening() {
        // Listen for space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        log("Started listening for space changes")
    }

    @objc func spaceDidChange(_ notification: Notification) {
        // Re-apply wallpaper on space change to ensure consistency
        log("Space changed - re-applying wallpaper")
        setWallpaper(style: mapStyle)
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            if self?.autoRefreshEnabled == true {
                log("Auto-refreshing wallpaper...")
                self?.generateAndSetWallpaper()
            }
        }
    }

    func generateAndSetWallpaper() {
        // Prevent concurrent generations
        guard !isGenerating else {
            log("Already generating, skipping...")
            return
        }
        isGenerating = true

        // Capture current style at start - don't let it change mid-generation
        let styleToGenerate = self.mapStyle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer { self.isGenerating = false }

            // Run the Node.js script to generate the wallpaper
            let scriptPath = self.getScriptDirectory() + "/generate.js"

            // Check if script exists
            if !FileManager.default.fileExists(atPath: scriptPath) {
                log("Error: generate.js not found at \(scriptPath)")
                return
            }

            log("Generating wallpaper (style: \(styleToGenerate.rawValue))...")

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["node", scriptPath, "--no-set", "--style=\(styleToGenerate.rawValue)"]
            task.currentDirectoryURL = URL(fileURLWithPath: self.getScriptDirectory())

            // Capture output
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    log("Script output: \(output)")
                }

                if task.terminationStatus == 0 {
                    log("Wallpaper generated successfully")
                    // Set for all spaces with the style we just generated
                    DispatchQueue.main.async {
                        self.setWallpaper(style: styleToGenerate)
                    }
                } else {
                    log("Script failed with status: \(task.terminationStatus)")
                }
            } catch {
                log("Failed to run script: \(error)")
            }
        }
    }

    func setWallpaper(style: MapStyle) {
        // Use style-specific filename to bust macOS cache
        let wallpaperPath = getScriptDirectory() + "/wallpaper-\(style.rawValue).png"
        let sourcePath = getScriptDirectory() + "/wallpaper.png"

        // Copy the generated wallpaper to a style-specific file
        do {
            if FileManager.default.fileExists(atPath: wallpaperPath) {
                try FileManager.default.removeItem(atPath: wallpaperPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: wallpaperPath)
        } catch {
            log("ERROR: Failed to copy wallpaper: \(error)")
            return
        }

        guard FileManager.default.fileExists(atPath: wallpaperPath) else {
            log("ERROR: Wallpaper file not found at \(wallpaperPath)")
            return
        }

        log("Setting wallpaper for all spaces (\(style.rawValue))...")

        // Use AppleScript to set wallpaper on ALL desktops/spaces
        let script = """
        tell application "System Events"
            tell every desktop
                set picture to "\(wallpaperPath)"
            end tell
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                log("SUCCESS: Set wallpaper on all spaces")
                DispatchQueue.main.async {
                    self.onWallpaperSet?()
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "unknown error"
                log("ERROR: AppleScript failed: \(output)")
            }
        } catch {
            log("ERROR: Failed to run AppleScript: \(error)")
        }
    }

    private func getScriptDirectory() -> String {
        // Check for environment variable first
        if let envPath = ProcessInfo.processInfo.environment["HEMISPHERE_SCRIPTS_DIR"] {
            return envPath
        }

        // Try to find scripts relative to the executable
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let possiblePaths = [
            // Parent of .build/debug/Hemisphere (development)
            executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path,
            // Same directory as executable
            executableURL.deletingLastPathComponent().path,
            // Current working directory
            FileManager.default.currentDirectoryPath
        ]

        for path in possiblePaths {
            let scriptPath = path + "/generate.js"
            if FileManager.default.fileExists(atPath: scriptPath) {
                return path
            }
        }

        // Fallback to current directory
        return FileManager.default.currentDirectoryPath
    }
}
