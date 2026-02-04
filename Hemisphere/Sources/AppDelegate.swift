import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var wallpaperManager: WallpaperManager?

    // Menu items
    var lastUpdatedMenuItem: NSMenuItem?
    var satelliteMenuItem: NSMenuItem?
    var darkMenuItem: NSMenuItem?
    var lightMenuItem: NSMenuItem?

    // Refresh interval menu
    var refreshIntervalMenuItems: [NSMenuItem] = []
    let refreshIntervalOptions: [(title: String, seconds: Int)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]

    // Region menu
    var regionMenuItems: [NSMenuItem] = []

    // Weather layer menu items
    var radarLayerMenuItem: NSMenuItem?

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

        // Region submenu
        let regionMenu = NSMenu()
        for (index, region) in MapRegion.all.enumerated() {
            let item = NSMenuItem(title: region.name, action: #selector(setRegion(_:)), keyEquivalent: "")
            item.tag = index
            item.state = index == 0 ? .on : .off  // Default: Continental US
            regionMenu.addItem(item)
            regionMenuItems.append(item)
        }

        let regionItem = NSMenuItem(title: "Region", action: nil, keyEquivalent: "")
        regionItem.submenu = regionMenu
        menu.addItem(regionItem)

        // Radar layer toggle
        radarLayerMenuItem = NSMenuItem(title: "Show Radar", action: #selector(toggleRadarLayer(_:)), keyEquivalent: "")
        radarLayerMenuItem?.state = .on
        menu.addItem(radarLayerMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // Auto-refresh toggle
        let autoRefreshItem = NSMenuItem(title: "Auto-Refresh", action: #selector(toggleAutoRefresh), keyEquivalent: "")
        autoRefreshItem.state = .on
        menu.addItem(autoRefreshItem)

        // Refresh interval submenu
        let refreshIntervalMenu = NSMenu()
        for option in refreshIntervalOptions {
            let item = NSMenuItem(title: option.title, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.tag = option.seconds
            item.state = option.seconds == 600 ? .on : .off  // Default 10 minutes
            refreshIntervalMenu.addItem(item)
            refreshIntervalMenuItems.append(item)
        }

        let refreshIntervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        refreshIntervalItem.submenu = refreshIntervalMenu
        menu.addItem(refreshIntervalItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu

        // Initialize wallpaper manager
        wallpaperManager = WallpaperManager()
        wallpaperManager?.onGenerationStarted = { [weak self] in
            self?.showLoadingState()
        }
        wallpaperManager?.onGenerationEnded = { [weak self] in
            self?.hideLoadingState()
        }
        wallpaperManager?.onWallpaperSet = { [weak self] in
            self?.updateLastUpdatedTime()
        }
        wallpaperManager?.startListening()

        // Update menu checkmarks to reflect loaded preferences
        updateAllMenuCheckmarks()

        // Initial wallpaper set
        refreshWallpaper()
    }

    func updateAllMenuCheckmarks() {
        guard let wm = wallpaperManager else { return }

        // Map style
        updateStyleCheckmarks()

        // Region
        for item in regionMenuItems {
            item.state = item.tag == wm.regionIndex ? .on : .off
        }

        // Refresh interval
        let interval = Int(wm.refreshInterval)
        for item in refreshIntervalMenuItems {
            item.state = item.tag == interval ? .on : .off
        }

        // Auto-refresh - find the menu item
        if let menu = statusItem?.menu {
            for item in menu.items where item.title == "Auto-Refresh" {
                item.state = wm.autoRefreshEnabled ? .on : .off
            }
        }

        // Weather layers
        radarLayerMenuItem?.state = wm.radarLayerEnabled ? .on : .off
    }

    func updateLastUpdatedTime() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: Date())
        lastUpdatedMenuItem?.title = "Last updated: \(timeString)"
    }

    func showLoadingState() {
        DispatchQueue.main.async {
            self.lastUpdatedMenuItem?.title = "Generating..."
            LoadingOverlay.shared.show()
        }
    }

    func hideLoadingState() {
        DispatchQueue.main.async {
            LoadingOverlay.shared.hide()
        }
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

    @objc func setRefreshInterval(_ sender: NSMenuItem) {
        let seconds = sender.tag
        wallpaperManager?.refreshInterval = TimeInterval(seconds)

        // Update checkmarks
        for item in refreshIntervalMenuItems {
            item.state = item.tag == seconds ? .on : .off
        }
    }

    @objc func setRegion(_ sender: NSMenuItem) {
        let index = sender.tag
        wallpaperManager?.regionIndex = index

        // Update checkmarks
        for item in regionMenuItems {
            item.state = item.tag == index ? .on : .off
        }

        refreshWallpaper()
    }

    @objc func toggleRadarLayer(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        wallpaperManager?.radarLayerEnabled = sender.state == .on
        refreshWallpaper()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
