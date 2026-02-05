import Foundation

struct Preferences {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let mapStyle = "mapStyle"
        static let regionIndex = "regionIndex"
        static let refreshInterval = "refreshInterval"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let radarLayerEnabled = "radarLayerEnabled"
        static let satelliteLayerEnabled = "satelliteLayerEnabled"
    }

    static var mapStyle: MapStyle {
        get {
            if let raw = defaults.string(forKey: Keys.mapStyle),
               let style = MapStyle(rawValue: raw) {
                return style
            }
            return .satellite
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.mapStyle) }
    }

    static var regionIndex: Int {
        get { defaults.object(forKey: Keys.regionIndex) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Keys.regionIndex) }
    }

    static var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.refreshInterval)
            return value > 0 ? value : 600  // Default 10 minutes
        }
        set { defaults.set(newValue, forKey: Keys.refreshInterval) }
    }

    static var autoRefreshEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoRefreshEnabled) == nil {
                return true  // Default to enabled
            }
            return defaults.bool(forKey: Keys.autoRefreshEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.autoRefreshEnabled) }
    }

    static var radarLayerEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.radarLayerEnabled) == nil {
                return true  // Default to enabled
            }
            return defaults.bool(forKey: Keys.radarLayerEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.radarLayerEnabled) }
    }

    static var satelliteLayerEnabled: Bool {
        get { defaults.bool(forKey: Keys.satelliteLayerEnabled) }  // Default to disabled
        set { defaults.set(newValue, forKey: Keys.satelliteLayerEnabled) }
    }
}
