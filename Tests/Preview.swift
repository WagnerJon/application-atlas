import SwiftUI

@main struct PreviewApp: App {
    @StateObject private var store: ApplicationStore
    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atlas-preview-\(UUID().uuidString)")
        let store = ApplicationStore(directory: directory)
        let mapStore = MapLocationStore(directory: directory)
        let cities = [
            MapPlace(name: "Berlin, Germany", latitude: 52.52, longitude: 13.405),
            MapPlace(name: "Paris, France", latitude: 48.8566, longitude: 2.3522),
            MapPlace(name: "Zurich, Switzerland", latitude: 47.3769, longitude: 8.5417),
            MapPlace(name: "Cambridge, United Kingdom", latitude: 52.2053, longitude: 0.1218)
        ]
        for city in cities { mapStore.setCity(city.name, place: city) }
        let statuses: [ApplicationStatus] = [.rejected, .offer, .interview, .sent]
        for (index, status) in statuses.enumerated() {
            var record = Application()
            record.role = ["Research associate", "Doctoral researcher", "Software engineer", "PhD in Biology"][index]
            record.organization = "Preview University \(index + 1)"
            record.location = cities[index].name
            record.kind = index % 2 == 0 ? .job : .phd
            record.status = .sent
            record.sentDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            record.statusHistory = [StatusEvent(status: .sent, date: record.sentDate)]
            if status != .sent { record.addStep(.interview, on: Date()) }
            if [.rejected, .offer].contains(status) { record.addStep(status, on: Date()) }
            store.save(record)
        }
        _store = StateObject(wrappedValue: store)
    }
    var body: some Scene {
        WindowGroup("Atlas — disposable preview") {
            ContentView().environmentObject(store).frame(minWidth: 1040, minHeight: 720).tint(.teal)
        }.defaultSize(width: 1220, height: 850)
    }
}
