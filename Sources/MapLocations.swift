import SwiftUI
import MapKit
import CoreLocation

struct MapPlace: Codable, Equatable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(latitude),\(longitude):\(name)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    static let heidelberg = MapPlace(name: "Heidelberg, Germany", latitude: 49.3988, longitude: 8.6724)
}
struct MapPreferences: Codable {
    var home = MapPlace.heidelberg
    var cities: [String: MapPlace] = [:]
}
@MainActor final class MapLocationStore: ObservableObject {
    @Published private(set) var preferences = MapPreferences()
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var alternatives: [String: [MapPlace]] = [:]
    @Published private(set) var resolving = false
    @Published var error: String?
    private let file: URL
    private var canSave = true
    init(directory: URL) {
        file = directory.appendingPathComponent("map-settings.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                preferences = try JSONDecoder().decode(MapPreferences.self, from: Data(contentsOf: file))
            }
        } catch {
            canSave = false
            self.error = "Map settings could not be loaded. The existing file has been preserved. \(error.localizedDescription)"
        }
    }
    static func key(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    func place(for city: String) -> MapPlace? { preferences.cities[Self.key(city)] }
    @discardableResult func setHome(_ place: MapPlace) -> Bool {
        var updated = preferences; updated.home = place
        return persist(updated)
    }
    @discardableResult func setCity(_ city: String, place: MapPlace) -> Bool {
        var updated = preferences; updated.cities[Self.key(city)] = place
        guard persist(updated) else { return false }
        failures[Self.key(city)] = nil; alternatives[Self.key(city)] = nil
        return true
    }
    private func persist(_ preferences: MapPreferences) -> Bool {
        guard canSave else { error = "Restore the map-settings.json file and reopen the app before saving map settings."; return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: file, options: .atomic)
            self.preferences = preferences
            return true
        } catch { self.error = "Could not save map settings: \(error.localizedDescription)"; return false }
    }
    static func search(_ city: String) async throws -> [MapPlace] {
        let geocoder = CLGeocoder()
        let results = try await geocoder.geocodeAddressString(city)
        try Task.checkCancellation()
        var seen = Set<String>()
        return results.compactMap { result in
            guard let coordinate = result.location?.coordinate else { return nil }
            let name = [result.locality ?? result.name, result.administrativeArea, result.country].compactMap { $0 }.joined(separator: ", ")
            let place = MapPlace(name: name.isEmpty ? city : name, latitude: coordinate.latitude, longitude: coordinate.longitude)
            let key = "\(Int(coordinate.latitude * 100)),\(Int(coordinate.longitude * 100))"
            return seen.insert(key).inserted ? place : nil
        }
    }
    func resolveMissing(_ cities: [String]) async {
        resolving = true
        defer { resolving = false }
        let unique = Dictionary(cities.map { (Self.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        for (key, city) in unique.sorted(by: { $0.key < $1.key }) where !key.isEmpty && preferences.cities[key] == nil {
            if Task.isCancelled { return }
            do {
                let matches = try await Self.search(city)
                if matches.count == 1, let place = matches.first { setCity(city, place: place) }
                else if matches.isEmpty { failures[key] = "City not found. Try a city and country." }
                else { alternatives[key] = matches; failures[key] = "Choose the correct city." }
            } catch {
                if Task.isCancelled { return }
                failures[key] = "Could not locate this city. Check your connection or use a city and country."
            }
            // Geocode serially and avoid bursts against Apple's service.
            do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
        }
    }
}

struct FlightRoute {
    let points: [MKMapPoint]
    var arrowCoordinate: CLLocationCoordinate2D { points[points.count * 3 / 4].coordinate }
    var arrowAngle: Double {
        let index = points.count * 3 / 4
        let a = points[index - 1], b = points[index + 1]
        return atan2(b.y - a.y, b.x - a.x) * 180 / .pi + 90
    }
    init(from: MapPlace, to: MapPlace, lane: Int = 0) {
        let a = MKMapPoint(from.coordinate)
        var b = MKMapPoint(to.coordinate)
        let world = MKMapRect.world.size.width
        // Use the short path across the date line rather than circling the world.
        if b.x - a.x > world / 2 { b.x -= world }
        if b.x - a.x < -world / 2 { b.x += world }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let bend = 0.18 + Double(lane % 6) * 0.09
        let control = MKMapPoint(x: (a.x + b.x) / 2 + dy * bend, y: (a.y + b.y) / 2 - dx * bend)
        if length < 100 {
            // A small loop keeps positions in the home city visible.
            let radius = 7000.0 + Double(lane % 6) * 2500
            points = (0...64).map { step in
                let angle = Double(step) / 64 * 2 * .pi
                return MKMapPoint(x: a.x + radius * sin(angle), y: a.y - radius * (1 - cos(angle)))
            }
        } else {
            points = (0...64).map { step in
                let t = Double(step) / 64, u = 1 - t
                return MKMapPoint(x: u*u*a.x + 2*u*t*control.x + t*t*b.x, y: u*u*a.y + 2*u*t*control.y + t*t*b.y)
            }
        }
    }
    static func visibleRect(home: MapPlace, routes: [FlightRoute]) -> MKMapRect {
        let center = MKMapPoint(home.coordinate)
        let points = routes.flatMap(\.points) + [center]
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let width = max(maxX - minX, 100_000), height = max(maxY - minY, 100_000)
        return MKMapRect(x: (minX + maxX) / 2 - width * 0.68, y: (minY + maxY) / 2 - height * 0.68, width: width * 1.36, height: height * 1.36)
    }
}
