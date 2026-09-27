import Foundation
import MapKit

@main struct StorageTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atlas-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ApplicationStore(directory: root)
        assert(store.error == nil)
        var record = Application()
        record.role = "Research fellow"; record.organization = "Test University"; record.kind = .phd
        record.status = .sent; record.sentDate = Date(timeIntervalSince1970: 1700000000)
        let original = root.appendingPathComponent("cover-letter.txt")
        try Data("Submitted letter version".utf8).write(to: original)
        let attachment = try store.importAttachment(original)
        record.attachments = [attachment]
        assert(store.save(record))
        let reloaded = ApplicationStore(directory: root)
        assert(reloaded.applications.count == 1)
        assert(reloaded.applications[0].sentDate == record.sentDate)
        assert(reloaded.applications[0].attachments[0].name == "cover-letter.txt")
        try Data("Changed original".utf8).write(to: original)
        let savedContents = try String(contentsOf: reloaded.fileURL(attachment), encoding: .utf8)
        assert(savedContents == "Submitted letter version")
        record.status = .interview
        assert(reloaded.save(record))
        assert(reloaded.applications.count == 1 && reloaded.applications[0].status == .interview)
        var interviewed = reloaded.applications[0]
        assert(interviewed.history.map(\.status) == [.sent, .interview])
        interviewed.addStep(.rejected, on: Date(timeIntervalSince1970: 1800000000))
        assert(reloaded.save(interviewed))
        let afterRejection = ApplicationStore(directory: root).applications[0]
        assert(afterRejection.status == .rejected)
        assert(afterRejection.history.map(\.status) == [.sent, .interview, .rejected])
        assert(afterRejection.reached(.interview) && afterRejection.reached(.rejected))
        assert(!afterRejection.reached(.offer))
        assert(reloaded.save(afterRejection))
        assert(reloaded.applications[0].history.count == 3, "Saving unchanged details must not duplicate steps")

        // Older databases have no statusHistory key and must remain readable.
        let encoded = try JSONEncoder().encode(record)
        var legacyObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyObject.removeValue(forKey: "statusHistory")
        let legacy = try JSONDecoder().decode(Application.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        assert(legacy.status == .interview && legacy.history.count == 1)
        assert(legacy.history[0].date == nil, "Migration must not invent a historical date")
        var migrated = legacy
        migrated.addStep(.offer, on: Date())
        assert(migrated.history.map(\.status) == [.interview, .offer])

        let pipeline = ApplicationPipeline([afterRejection, migrated])
        assert(pipeline.nodes.first { $0.id == "all" }?.count == 2)
        assert(pipeline.edges.contains { $0.source == "3:Interview" && $0.destination == "4:Rejected" && $0.count == 1 })
        assert(pipeline.edges.contains { $0.source == "2:Interview" && $0.destination == "3:Offer" && $0.count == 1 })
        for node in pipeline.nodes {
            let incoming = pipeline.edges.filter { $0.destination == node.id }.reduce(0) { $0 + $1.count }
            let outgoing = pipeline.edges.filter { $0.source == node.id }.reduce(0) { $0 + $1.count }
            if node.column > 0 { assert(incoming == node.count) }
            assert(outgoing <= node.count)
        }
        assert([afterRejection, migrated].filter { $0.reached(.rejected) }.count == 1)
        assert([afterRejection, migrated].filter { $0.reached(.interview) }.count == 2)
        var corrected = afterRejection
        let originalIDs = corrected.history.map(\.id)
        let newDate = Date(timeIntervalSince1970: 1750000000)
        corrected.updateStep(id: originalIDs[1], status: .response, date: newDate)
        assert(corrected.history.count == 3 && corrected.history.map(\.id) == originalIDs)
        assert(corrected.history[1].status == .response && corrected.history[1].date == newDate)
        assert(corrected.status == .rejected, "Editing an earlier step must not change the final status")
        corrected.updateStep(id: originalIDs[2], status: .offer, date: newDate)
        assert(corrected.status == .offer && !corrected.reached(.rejected))
        assert(reloaded.save(corrected))
        let persistedCorrection = ApplicationStore(directory: root).applications[0]
        assert(persistedCorrection.history.count == 3, "Editing must not append a new step on save")
        assert(persistedCorrection.history.map(\.id) == originalIDs)
        assert(persistedCorrection.history[1].date == newDate && persistedCorrection.status == .offer)
        let correctedPipeline = ApplicationPipeline([persistedCorrection])
        assert(correctedPipeline.edges.contains { $0.source == "3:Response received" && $0.destination == "4:Offer" })
        corrected.updateStep(id: originalIDs[0], status: .sent, date: newDate)
        assert(corrected.sentDate == newDate)
        var editedLegacy = legacy
        editedLegacy.updateStep(id: legacy.history[0].id, status: .withdrawn, date: newDate)
        assert(editedLegacy.status == .withdrawn && editedLegacy.history.count == 1 && editedLegacy.history[0].date == newDate)
        corrected.updateStep(id: originalIDs[1], status: .interview, date: nil)
        assert(corrected.history[1].date == nil)
        let orphan = try reloaded.importAttachment(original)
        reloaded.removeUnused([orphan, attachment])
        assert(!FileManager.default.fileExists(atPath: reloaded.fileURL(orphan).path))
        assert(FileManager.default.fileExists(atPath: reloaded.fileURL(attachment).path))
        assert(reloaded.delete(record))
        assert(!FileManager.default.fileExists(atPath: reloaded.fileURL(attachment).path))
        assert(FileManager.default.fileExists(atPath: original.path))
        assert(ApplicationStore(directory: root).applications.isEmpty)
        try Data("invalid json".utf8).write(to: reloaded.database)
        let broken = ApplicationStore(directory: root)
        assert(!broken.canWrite && broken.error != nil)
        assert(!broken.save(record))
        let preserved = try String(contentsOf: reloaded.database, encoding: .utf8)
        assert(preserved == "invalid json")
        let mapDirectory = root.appendingPathComponent("MapTests")
        let mapStore = MapLocationStore(directory: mapDirectory)
        assert(mapStore.preferences.home == .heidelberg)
        let paris = MapPlace(name: "Paris, France", latitude: 48.8566, longitude: 2.3522)
        let berlin = MapPlace(name: "Berlin, Germany", latitude: 52.52, longitude: 13.405)
        assert(mapStore.setHome(paris))
        assert(mapStore.setCity("  Berlin, Germany  ", place: berlin))
        let mapReloaded = MapLocationStore(directory: mapDirectory)
        assert(mapReloaded.preferences.home == paris)
        assert(mapReloaded.place(for: "BERLIN, GERMANY") == berlin)
        assert(mapReloaded.place(for: "Unknown city") == nil)
        let flight = FlightRoute(from: paris, to: berlin)
        assert(flight.points.count == 65 && flight.arrowAngle.isFinite)
        assert(abs(flight.points.first!.coordinate.latitude - paris.latitude) < 0.00001)
        assert(abs(flight.points.last!.coordinate.longitude - berlin.longitude) < 0.00001)
        let alternateLane = FlightRoute(from: paris, to: berlin, lane: 1)
        assert(flight.points[32].x != alternateLane.points[32].x)
        let sameCity = FlightRoute(from: paris, to: paris)
        assert(sameCity.arrowAngle.isFinite)
        assert(hypot(sameCity.points.last!.x - sameCity.points.first!.x, sameCity.points.last!.y - sameCity.points.first!.y) < 1)
        let acrossDateLine = FlightRoute(from: MapPlace(name: "West", latitude: 10, longitude: 179), to: MapPlace(name: "East", latitude: 10, longitude: -179))
        assert(abs(acrossDateLine.points.last!.x - acrossDateLine.points.first!.x) < MKMapRect.world.size.width / 20)
        let bounds = FlightRoute.visibleRect(home: paris, routes: [flight, alternateLane])
        assert(bounds.size.width > 0 && bounds.size.height > 0)
        assert((flight.points + alternateLane.points).allSatisfy { bounds.contains($0) })
        assert(FlightRoute.visibleRect(home: paris, routes: []).size.width > 0)
        print("PASS: storage, journey editing, Sankey, map settings/cache persistence, route endpoints/lanes/arrows, same-city and date-line geometry")
    }
}
