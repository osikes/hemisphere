import AppKit
import MapKit

class WallpaperManager {
    var mapStyle: MapStyle {
        didSet { Preferences.mapStyle = mapStyle }
    }
    var regionIndex: Int {
        didSet { Preferences.regionIndex = regionIndex }
    }
    var region: MapRegion {
        get { MapRegion.all[regionIndex] }
        set { regionIndex = MapRegion.all.firstIndex(where: { $0.name == newValue.name }) ?? 0 }
    }
    var autoRefreshEnabled: Bool {
        didSet { Preferences.autoRefreshEnabled = autoRefreshEnabled }
    }
    var radarLayerEnabled: Bool {
        didSet { Preferences.radarLayerEnabled = radarLayerEnabled }
    }
    var satelliteLayerEnabled: Bool {
        didSet { Preferences.satelliteLayerEnabled = satelliteLayerEnabled }
    }
    var onGenerationStarted: (() -> Void)?
    var onGenerationEnded: (() -> Void)?
    var onWallpaperSet: (() -> Void)?
    var refreshInterval: TimeInterval {
        didSet {
            Preferences.refreshInterval = refreshInterval
            startAutoRefresh()
        }
    }
    private var refreshTimer: Timer?
    private var isGenerating = false
    private var pendingRefresh = false
    private var currentWallpaperPath: String?

    init() {
        // Load saved preferences
        self.mapStyle = Preferences.mapStyle
        self.regionIndex = Preferences.regionIndex
        self.autoRefreshEnabled = Preferences.autoRefreshEnabled
        self.refreshInterval = Preferences.refreshInterval
        self.radarLayerEnabled = Preferences.radarLayerEnabled
        self.satelliteLayerEnabled = Preferences.satelliteLayerEnabled
        startAutoRefresh()
    }

    func startListening() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        log("Started listening for space changes")
    }

    @objc func spaceDidChange(_ notification: Notification) {
        log("Space changed - re-applying wallpaper")
        if let path = currentWallpaperPath {
            applyWallpaper(path: path)
        }
    }

    func startAutoRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshTimer?.invalidate()
            let timer = Timer(timeInterval: self.refreshInterval, repeats: true) { [weak self] _ in
                if self?.autoRefreshEnabled == true {
                    let interval = Int(self?.refreshInterval ?? 0)
                    let intervalStr = interval < 60 ? "\(interval) sec" : "\(interval / 60) min"
                    log("Auto-refreshing wallpaper (interval: \(intervalStr))...")
                    self?.generateAndSetWallpaper()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.refreshTimer = timer
            log("Timer scheduled with interval: \(Int(self.refreshInterval)) seconds")
        }
    }

    func generateAndSetWallpaper() {
        guard !isGenerating else {
            log("Already generating, queuing refresh...")
            pendingRefresh = true
            return
        }
        isGenerating = true
        pendingRefresh = false
        onGenerationStarted?()

        let styleToGenerate = self.mapStyle
        let regionToGenerate = self.region
        let radarEnabled = self.radarLayerEnabled
        let satelliteEnabled = self.satelliteLayerEnabled

        log("Generating wallpaper (style: \(styleToGenerate.rawValue), region: \(regionToGenerate.name), radar: \(radarEnabled), satellite: \(satelliteEnabled))...")

        // Fetch weather layer data from RainViewer API
        fetchWeatherLayers { [weak self] layers in
            guard let self = self else { return }

            if let radarPath = layers.radarPath {
                log("Got radar path: \(radarPath)")
            }
            if let satellitePath = layers.satellitePath {
                log("Got satellite path: \(satellitePath)")
            }

            // Only use paths for enabled layers
            let activeLayers = WeatherLayers(
                radarPath: radarEnabled ? layers.radarPath : nil,
                satellitePath: satelliteEnabled ? layers.satellitePath : nil
            )

            // Generate the map snapshot on main thread (required for MapKit)
            DispatchQueue.main.async {
                self.generateMapSnapshot(style: styleToGenerate, region: regionToGenerate, layers: activeLayers) { [weak self] image in
                    guard let self = self else { return }

                    defer {
                        self.isGenerating = false
                        self.onGenerationEnded?()
                        if self.pendingRefresh {
                            log("Processing pending refresh...")
                            self.generateAndSetWallpaper()
                        }
                    }

                    guard let image = image else {
                        log("ERROR: Failed to generate map snapshot")
                        return
                    }

                    // Save and set wallpaper
                    if let path = self.saveWallpaper(image: image) {
                        self.currentWallpaperPath = path
                        self.applyWallpaper(path: path)
                    }
                }
            }
        }
    }

    private func fetchWeatherLayers(completion: @escaping (WeatherLayers) -> Void) {
        let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                log("ERROR: Failed to fetch weather data: \(error?.localizedDescription ?? "unknown")")
                completion(WeatherLayers())
                return
            }

            do {
                let response = try JSONDecoder().decode(RainViewerResponse.self, from: data)
                var layers = WeatherLayers()

                // Get latest radar frame
                if let latestRadar = response.radar.past.last {
                    layers.radarPath = latestRadar.path
                    log("Radar frames available: \(response.radar.past.count)")
                }

                // Get latest satellite frame
                if let satellite = response.satellite {
                    log("Satellite data present in response")
                    if let infrared = satellite.infrared {
                        log("Infrared frames available: \(infrared.count)")
                        if let latestSatellite = infrared.last {
                            layers.satellitePath = latestSatellite.path
                            log("Using satellite path: \(latestSatellite.path)")
                        }
                    } else {
                        log("No infrared data in satellite response")
                    }
                } else {
                    log("No satellite data in API response")
                }

                completion(layers)
            } catch {
                log("ERROR: Failed to decode weather response: \(error)")
                // Log raw response for debugging
                if let rawString = String(data: data, encoding: .utf8) {
                    log("Raw API response (first 500 chars): \(String(rawString.prefix(500)))")
                }
                completion(WeatherLayers())
            }
        }.resume()
    }

    private func generateMapSnapshot(style: MapStyle, region: MapRegion, layers: WeatherLayers, completion: @escaping (NSImage?) -> Void) {
        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        let size = screen.frame.size

        // Create coordinate region - wider for landscape screens
        let center = CLLocationCoordinate2D(latitude: region.lat, longitude: region.lon)
        let latSpan = region.span
        let lonSpan = region.span * (size.width / size.height)  // Adjust for screen aspect ratio
        let mapSpan = MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        let mapRegion = MKCoordinateRegion(center: center, span: mapSpan)

        log("Map snapshot: center=(\(region.lat), \(region.lon)), span=(\(latSpan), \(lonSpan)), size=\(size)")

        // For blackout style, use CartoDB Dark Matter tiles instead of MapKit
        if style == .blackout {
            generateDarkMapWithTiles(mapRegion: mapRegion, size: size, layers: layers, completion: completion)
            return
        }

        // Configure map snapshot options for other styles
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.region = mapRegion

        // Set map style (avoid flyover types which show 3D globe)
        switch style {
        case .satellite:
            options.mapType = .hybrid
        case .dark:
            options.mapType = .mutedStandard
        case .light:
            options.mapType = .standard
        case .blackout:
            break // Handled above
        }

        // Disable POI for cleaner map
        options.pointOfInterestFilter = .excludingAll

        // Ensure we're showing a flat map, not 3D
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)

        snapshotter.start { [weak self] snapshot, error in
            guard let snapshot = snapshot, error == nil else {
                log("ERROR: Map snapshot failed: \(error?.localizedDescription ?? "unknown")")
                completion(nil)
                return
            }

            // Overlay weather layers
            if layers.satellitePath != nil || layers.radarPath != nil {
                self?.overlayWeatherLayers(on: snapshot, layers: layers, mapRegion: mapRegion, size: size, completion: completion)
            } else {
                completion(snapshot.image)
            }
        }
    }

    private func generateDarkMapWithTiles(mapRegion: MKCoordinateRegion, size: CGSize, layers: WeatherLayers, completion: @escaping (NSImage?) -> Void) {
        // Use a higher zoom level for dark tiles to get better coverage and quality
        let tiles = calculateTilesForRegion(mapRegion: mapRegion, size: size, minZoom: 5)

        log("Fetching \(tiles.count) CartoDB Dark Matter tiles at zoom \(tiles.first?.z ?? 0)...")

        let group = DispatchGroup()
        var baseTiles: [(tile: (x: Int, y: Int, z: Int), image: NSImage)] = []
        var radarTiles: [(tile: (x: Int, y: Int, z: Int), image: NSImage)] = []
        let lock = NSLock()

        // Fetch CartoDB Dark Matter tiles with retina resolution
        let subdomains = ["a", "b", "c", "d"]
        for (index, tile) in tiles.enumerated() {
            group.enter()
            let subdomain = subdomains[index % subdomains.count]
            let urlString = "https://\(subdomain).basemaps.cartocdn.com/dark_all/\(tile.z)/\(tile.x)/\(tile.y)@2x.png"

            guard let url = URL(string: urlString) else {
                log("Invalid dark tile URL for tile \(tile)")
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                if let error = error {
                    log("Dark tile error for \(tile): \(error.localizedDescription)")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    log("Dark tile HTTP \(httpResponse.statusCode) for \(tile)")
                    return
                }
                if let data = data, let image = NSImage(data: data) {
                    lock.lock()
                    baseTiles.append((tile, image))
                    lock.unlock()
                }
            }.resume()
        }

        // Fetch radar tiles if enabled
        if let radarPath = layers.radarPath {
            for tile in tiles {
                group.enter()
                let urlString = "https://tilecache.rainviewer.com\(radarPath)/512/\(tile.z)/\(tile.x)/\(tile.y)/2/1_1.png"
                guard let url = URL(string: urlString) else {
                    group.leave()
                    continue
                }

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { group.leave() }
                    if let data = data, let image = NSImage(data: data) {
                        lock.lock()
                        radarTiles.append((tile, image))
                        lock.unlock()
                    }
                }.resume()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            log("Downloaded \(baseTiles.count)/\(tiles.count) dark tiles, \(radarTiles.count) radar tiles")

            // Composite all tiles
            let finalImage = NSImage(size: size)
            finalImage.lockFocus()

            // Fill with dark background first (CartoDB dark uses this color)
            NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0).setFill()
            NSRect(origin: .zero, size: size).fill()

            // Draw base dark tiles
            for (tile, tileImage) in baseTiles {
                let rect = self.tileToRect(tile: tile, mapRegion: mapRegion, size: size)
                tileImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            // Draw radar tiles on top with transparency
            for (tile, tileImage) in radarTiles {
                let rect = self.tileToRect(tile: tile, mapRegion: mapRegion, size: size)
                tileImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7)
            }

            finalImage.unlockFocus()
            completion(finalImage)
        }
    }

    private func overlayWeatherLayers(on snapshot: MKMapSnapshotter.Snapshot, layers: WeatherLayers, mapRegion: MKCoordinateRegion, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        // Calculate which tiles we need
        let tiles = calculateTilesForRegion(mapRegion: mapRegion, size: size)

        log("Overlay region: center=(\(mapRegion.center.latitude), \(mapRegion.center.longitude)), span=(\(mapRegion.span.latitudeDelta), \(mapRegion.span.longitudeDelta))")
        log("Fetching tiles at zoom \(tiles.first?.z ?? 0)...")

        let group = DispatchGroup()
        var satelliteTiles: [(tile: (x: Int, y: Int, z: Int), image: NSImage)] = []
        var radarTiles: [(tile: (x: Int, y: Int, z: Int), image: NSImage)] = []
        let lock = NSLock()

        // Fetch satellite tiles if enabled
        if let satellitePath = layers.satellitePath {
            log("Fetching satellite tiles with path: \(satellitePath)")
            for tile in tiles {
                group.enter()
                // Satellite infrared tile URL
                let urlString = "https://tilecache.rainviewer.com\(satellitePath)/512/\(tile.z)/\(tile.x)/\(tile.y)/0/0_0.png"

                guard let url = URL(string: urlString) else {
                    log("Invalid satellite URL: \(urlString)")
                    group.leave()
                    continue
                }

                URLSession.shared.dataTask(with: url) { data, response, error in
                    defer { group.leave() }
                    if let error = error {
                        log("Satellite tile error: \(error.localizedDescription)")
                        return
                    }
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        log("Satellite tile HTTP \(httpResponse.statusCode) for \(tile)")
                        return
                    }
                    if let data = data, let image = NSImage(data: data) {
                        lock.lock()
                        satelliteTiles.append((tile, image))
                        lock.unlock()
                    }
                }.resume()
            }
        } else {
            log("No satellite path available")
        }

        // Fetch radar tiles if enabled
        if let radarPath = layers.radarPath {
            for tile in tiles {
                group.enter()
                // Radar tile URL with color scheme 2 (TITAN)
                let urlString = "https://tilecache.rainviewer.com\(radarPath)/512/\(tile.z)/\(tile.x)/\(tile.y)/2/1_1.png"
                guard let url = URL(string: urlString) else {
                    group.leave()
                    continue
                }

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { group.leave() }
                    if let data = data, let image = NSImage(data: data) {
                        lock.lock()
                        radarTiles.append((tile, image))
                        lock.unlock()
                    }
                }.resume()
            }
        }

        group.notify(queue: .main) {
            log("Downloaded \(satelliteTiles.count) satellite tiles, \(radarTiles.count) radar tiles")

            // Composite the tiles onto the map snapshot
            let finalImage = NSImage(size: size)
            finalImage.lockFocus()

            // Draw base map
            snapshot.image.draw(in: NSRect(origin: .zero, size: size))

            // Draw satellite tiles first (below radar) with transparency
            for (tile, tileImage) in satelliteTiles {
                let rect = self.tileToRect(tile: tile, mapRegion: mapRegion, size: size)
                tileImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            }

            // Draw radar tiles on top with transparency
            for (tile, tileImage) in radarTiles {
                let rect = self.tileToRect(tile: tile, mapRegion: mapRegion, size: size)
                tileImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7)
            }

            finalImage.unlockFocus()
            completion(finalImage)
        }
    }

    private func calculateTilesForRegion(mapRegion: MKCoordinateRegion, size: CGSize, minZoom: Int = 4) -> [(x: Int, y: Int, z: Int)] {
        let latSpan = mapRegion.span.latitudeDelta

        // Determine appropriate zoom level based on latitude span
        var z: Int
        if latSpan >= 30 {
            z = 4
        } else if latSpan >= 15 {
            z = 5
        } else if latSpan >= 8 {
            z = 6
        } else if latSpan >= 4 {
            z = 7
        } else {
            z = 8
        }

        // Ensure minimum zoom level
        z = max(z, minZoom)

        // Calculate tile coordinates for the region bounds with a small buffer
        let buffer = 0.05  // 5% buffer to ensure full coverage
        let minLat = mapRegion.center.latitude - mapRegion.span.latitudeDelta / 2 * (1 + buffer)
        let maxLat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2 * (1 + buffer)
        let minLon = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2 * (1 + buffer)
        let maxLon = mapRegion.center.longitude + mapRegion.span.longitudeDelta / 2 * (1 + buffer)

        let minTile = latLonToTile(lat: maxLat, lon: minLon, zoom: z)
        let maxTile = latLonToTile(lat: minLat, lon: maxLon, zoom: z)

        var tiles: [(x: Int, y: Int, z: Int)] = []
        for x in minTile.x...maxTile.x {
            for y in minTile.y...maxTile.y {
                tiles.append((x, y, z))
            }
        }
        return tiles
    }

    private func latLonToTile(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int((lon + 180.0) / 360.0 * n)
        let latRad = lat * .pi / 180.0
        let y = Int((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)
        return (x, y)
    }

    private func tileToRect(tile: (x: Int, y: Int, z: Int), mapRegion: MKCoordinateRegion, size: CGSize) -> NSRect {
        let n = pow(2.0, Double(tile.z))

        // Tile bounds in lon/lat
        let tileLonMin = Double(tile.x) / n * 360.0 - 180.0
        let tileLonMax = Double(tile.x + 1) / n * 360.0 - 180.0
        let tileLatMax = atan(sinh(.pi * (1 - 2 * Double(tile.y) / n))) * 180.0 / .pi
        let tileLatMin = atan(sinh(.pi * (1 - 2 * Double(tile.y + 1) / n))) * 180.0 / .pi

        // Region bounds
        let regionLatMin = mapRegion.center.latitude - mapRegion.span.latitudeDelta / 2
        let regionLonMin = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2

        // Convert to screen coordinates
        // x: longitude maps left to right
        let x = (tileLonMin - regionLonMin) / mapRegion.span.longitudeDelta * size.width
        // y: In NSImage, y=0 is at bottom, so lower latitudes = lower y
        let y = (tileLatMin - regionLatMin) / mapRegion.span.latitudeDelta * size.height
        let width = (tileLonMax - tileLonMin) / mapRegion.span.longitudeDelta * size.width
        let height = (tileLatMax - tileLatMin) / mapRegion.span.latitudeDelta * size.height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func saveWallpaper(image: NSImage) -> String? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let directory = getWallpaperDirectory()
        let path = "\(directory)/wallpaper-\(timestamp).png"

        // Clean up old wallpapers
        cleanupOldWallpapers(in: directory)

        // Save as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            log("ERROR: Failed to create PNG data")
            return nil
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            log("Wallpaper saved to: \(path)")
            return path
        } catch {
            log("ERROR: Failed to save wallpaper: \(error)")
            return nil
        }
    }

    private func applyWallpaper(path: String) {
        log("Setting wallpaper for all spaces...")

        let script = """
        tell application "System Events"
            tell every desktop
                set picture to "\(path)"
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

    private func cleanupOldWallpapers(in directory: String) {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(atPath: directory)
            for file in files where file.hasPrefix("wallpaper-") && file.hasSuffix(".png") {
                let filePath = directory + "/" + file
                try? fileManager.removeItem(atPath: filePath)
            }
        } catch {
            // Ignore cleanup errors
        }
    }

    private func getWallpaperDirectory() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hemisphereDir = appSupport.appendingPathComponent("Hemisphere")

        if !FileManager.default.fileExists(atPath: hemisphereDir.path) {
            try? FileManager.default.createDirectory(at: hemisphereDir, withIntermediateDirectories: true)
        }

        return hemisphereDir.path
    }
}
