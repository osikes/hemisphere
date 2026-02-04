import Foundation
import MapKit

enum MapStyle: String {
    case satellite = "satellite"
    case dark = "dark"
    case blackout = "blackout"
    case light = "light"
}

struct MapRegion {
    let name: String
    let lat: Double
    let lon: Double
    let span: Double  // Degrees for MKCoordinateSpan

    static let all: [MapRegion] = [
        MapRegion(name: "Continental US", lat: 39.8, lon: -98.5, span: 35),
        MapRegion(name: "Northeast", lat: 42.5, lon: -73.5, span: 12),
        MapRegion(name: "Southeast", lat: 33.0, lon: -84.0, span: 12),
        MapRegion(name: "Midwest", lat: 41.5, lon: -89.0, span: 12),
        MapRegion(name: "Southwest", lat: 34.0, lon: -111.0, span: 12),
        MapRegion(name: "West Coast", lat: 37.5, lon: -121.0, span: 12),
        MapRegion(name: "Pacific Northwest", lat: 46.5, lon: -122.5, span: 12),
        MapRegion(name: "Texas", lat: 31.5, lon: -99.5, span: 12),
        MapRegion(name: "Florida", lat: 28.0, lon: -82.5, span: 8),
        MapRegion(name: "Alabama", lat: 32.8, lon: -86.8, span: 6)
    ]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var coordinateSpan: MKCoordinateSpan {
        MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
    }

    var coordinateRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: coordinateSpan)
    }
}
