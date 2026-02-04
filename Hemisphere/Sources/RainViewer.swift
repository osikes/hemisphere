import Foundation
import MapKit

// RainViewer API response structures
struct RainViewerResponse: Codable {
    let radar: RadarData
    let satellite: SatelliteData?
}

struct RadarData: Codable {
    let past: [RadarFrame]
}

struct RadarFrame: Codable {
    let time: Int
    let path: String
}

struct SatelliteData: Codable {
    let infrared: [SatelliteFrame]?
}

struct SatelliteFrame: Codable {
    let time: Int
    let path: String
}

// Weather layer data
struct WeatherLayers {
    var radarPath: String?
    var satellitePath: String?
}

// Custom tile overlay for RainViewer radar
class RadarTileOverlay: MKTileOverlay {
    let radarPath: String

    init(radarPath: String) {
        self.radarPath = radarPath
        // RainViewer tile URL format: https://tilecache.rainviewer.com{path}/512/{z}/{x}/{y}/2/1_1.png
        let template = "https://tilecache.rainviewer.com\(radarPath)/512/{z}/{x}/{y}/2/1_1.png"
        super.init(urlTemplate: template)
        self.tileSize = CGSize(width: 512, height: 512)
    }
}
