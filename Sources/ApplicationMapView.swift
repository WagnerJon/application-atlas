import SwiftUI
import MapKit

private struct MappedApplication: Identifiable {
    let application: Application
    let place: MapPlace
    let route: FlightRoute
    var id: UUID { application.id }
}
struct ApplicationMapView: View {
    let applications: [Application]
    let onEdit: (Application) -> Void
    @StateObject private var locations: MapLocationStore
    @State private var position: MapCameraPosition = .automatic
    @State private var statusFilter: ApplicationStatus?
    @State private var selected: UUID?
    @State private var choosingHome = false
    @State private var choosingCity: String?
    @State private var retry = 0
    init(applications: [Application], directory: URL, onEdit: @escaping (Application) -> Void) {
        self.applications = applications
        self.onEdit = onEdit
        _locations = StateObject(wrappedValue: MapLocationStore(directory: directory))
    }
    private var cityNames: [String] {
        Array(Set(applications.map(\.location).filter { !MapLocationStore.key($0).isEmpty })).sorted()
    }
    private var mapped: [MappedApplication] {
        var lanes: [String: Int] = [:]
        return applications.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { application in
            guard let place = locations.place(for: application.location) else { return nil }
            let lane = lanes[place.id, default: 0]
            lanes[place.id] = lane + 1
            guard statusFilter == nil || application.status == statusFilter else { return nil }
            return MappedApplication(application: application, place: place, route: FlightRoute(from: locations.preferences.home, to: place, lane: lane))
        }
    }
    private var missing: [Application] {
        applications.filter { !MapLocationStore.key($0.location).isEmpty && locations.place(for: $0.location) == nil }
    }
    private var mapFingerprint: String {
        locations.preferences.home.id + mapped.map { $0.id.uuidString + $0.place.id }.joined()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("A world of possibilities.").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Your next chapter, seen from home.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { fitRoutes() } label: { Label("Fit all routes", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                HStack(spacing: 16) {
                    Image(systemName: "house.fill").font(.title2).foregroundStyle(.teal)
                        .frame(width: 44, height: 44).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOME BASE").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                        Text(locations.preferences.home.name).font(.headline)
                    }
                    Button("Change home…") { choosingHome = true }
                    Spacer()
                    Text("\(mapped.count) routes").font(.headline)
                    if locations.resolving { ProgressView().controlSize(.small); Text("Locating cities…").font(.caption).foregroundStyle(.secondary) }
                }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Where opportunity takes you").font(.title3.weight(.semibold))
                        Spacer()
                        Picker("Status", selection: $statusFilter) {
                            Text("All statuses").tag(nil as ApplicationStatus?)
                            ForEach(ApplicationStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                        }.labelsHidden().frame(width: 180)
                    }
                    routeMap
                        .frame(height: 440).clipShape(RoundedRectangle(cornerRadius: 12))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(ApplicationStatus.allCases) { status in
                            HStack(spacing: 6) { Circle().fill(status.color).frame(width: 7, height: 7); Text(status.rawValue).font(.caption) }
                        }
                    }
                    Text("Arrows point from home to each opportunity. Select a destination or route below to highlight it. Colors show current status.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 16))
                if applications.allSatisfy({ MapLocationStore.key($0.location).isEmpty }) {
                    ContentUnavailableView("Give your opportunities a place", systemImage: "mappin.and.ellipse", description: Text("Add a city and country in an application’s Location field to see a route from home."))
                        .frame(maxWidth: .infinity).padding(24).background(.background, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    routeList
                }
                Text("City lookup and map tiles use Apple’s services. Resolved cities and your home are saved on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }.background(Color(nsColor: .windowBackgroundColor))
        .task(id: cityNames.joined(separator: "|") + "-\(retry)") { await locations.resolveMissing(cityNames) }
        .onAppear { fitRoutes() }
        .onChange(of: mapFingerprint) { _, _ in
            if !mapped.contains(where: { $0.id == selected }) { selected = nil }
            fitRoutes()
        }
        .sheet(isPresented: $choosingHome) {
            CityPicker(title: "Set your home base", initialQuery: locations.preferences.home.name) { place in locations.setHome(place) }
        }
        .sheet(isPresented: Binding(get: { choosingCity != nil }, set: { if !$0 { choosingCity = nil } })) {
            if let city = choosingCity {
                CityPicker(title: "Locate application city", initialQuery: city, initialMatches: locations.alternatives[MapLocationStore.key(city)] ?? []) { place in locations.setCity(city, place: place) }
            }
        }
        .alert("Map settings", isPresented: Binding(get: { locations.error != nil }, set: { if !$0 { locations.error = nil } })) {
            Button("OK") { locations.error = nil }
        } message: { Text(locations.error ?? "") }
    }
    private var routeMap: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(mapped) { item in
                MapPolyline(points: item.route.points)
                    .stroke(item.application.status.color.opacity(selected == nil || selected == item.id ? 0.85 : 0.16), lineWidth: selected == item.id ? 4 : 2.5)
                Annotation("Route to \(item.place.name)", coordinate: item.route.arrowCoordinate) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: selected == item.id ? 15 : 11, weight: .bold))
                        .foregroundStyle(item.application.status.color)
                        .rotationEffect(.degrees(item.route.arrowAngle))
                        .opacity(selected == nil || selected == item.id ? 1 : 0.2)
                        .accessibilityHidden(true)
                }.annotationTitles(.hidden)
                Annotation(item.place.name, coordinate: item.place.coordinate) {
                    Button { selected = selected == item.id ? nil : item.id } label: {
                        Circle().fill(item.application.status.color).frame(width: selected == item.id ? 16 : 11, height: selected == item.id ? 16 : 11)
                            .overlay(Circle().stroke(.white, lineWidth: 2)).padding(5)
                    }.buttonStyle(.plain).help("\(item.application.role) · \(item.application.status.rawValue)")
                        .accessibilityLabel("\(item.application.role), \(item.place.name), \(item.application.status.rawValue)")
                }
            }
            Annotation("Home · \(locations.preferences.home.name)", coordinate: locations.preferences.home.coordinate) {
                Image(systemName: "house.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(9).background(.teal, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapScaleView(); MapZoomStepper() }
    }
    private var routeList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Destinations").font(.title3.weight(.semibold))
                Spacer()
                if !missing.isEmpty { Button("Retry city lookups") { retry += 1 }.disabled(locations.resolving) }
                if selected != nil { Button("Show all routes") { selected = nil } }
            }
            if mapped.isEmpty && missing.isEmpty { Text("No routes match this status.").foregroundStyle(.secondary) }
            ForEach(mapped) { item in
                HStack(spacing: 12) {
                    Button {
                        selected = selected == item.id ? nil : item.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paperplane.fill").foregroundStyle(item.application.status.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.application.role).fontWeight(.medium)
                                Text("\(item.application.organization) · \(item.place.name)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.application.status.rawValue).font(.caption).foregroundStyle(item.application.status.color)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button("Edit") { onEdit(item.application) }
                }.padding(10).background(selected == item.id ? item.application.status.color.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(missing) { application in
                HStack {
                    Image(systemName: "mappin.slash").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(application.role) · \(application.location)").fontWeight(.medium)
                        Text(locations.failures[MapLocationStore.key(application.location)] ?? "Waiting for city lookup…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Locate…") { choosingCity = application.location }
                    Button("Edit") { onEdit(application) }
                }.padding(10)
            }
            let withoutCity = applications.filter { MapLocationStore.key($0.location).isEmpty }.count
            if withoutCity > 0 { Text("\(withoutCity) applications have no city yet. Add a location in their details to include them on the map.").font(.caption).foregroundStyle(.secondary) }
        }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func fitRoutes() {
        position = .rect(FlightRoute.visibleRect(home: locations.preferences.home, routes: mapped.map(\.route)))
    }
}

private struct CityPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var query: String
    @State private var matches: [MapPlace]
    @State private var searching = false
    @State private var message: String?
    let onSelect: (MapPlace) -> Bool
    init(title: String, initialQuery: String, initialMatches: [MapPlace] = [], onSelect: @escaping (MapPlace) -> Bool) {
        self.title = title; self.onSelect = onSelect
        _query = State(initialValue: initialQuery); _matches = State(initialValue: initialMatches)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.bold())
            Text("Enter a city and country, then choose the correct location.").foregroundStyle(.secondary)
            HStack {
                TextField("City, country", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                Button("Find city") { search() }.disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if searching { ProgressView().controlSize(.small) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            ForEach(matches) { place in
                Button {
                    if onSelect(place) { dismiss() }
                    else { message = "The location could not be saved. Check the map settings error." }
                } label: { HStack { Image(systemName: "mappin.circle"); Text(place.name); Spacer(); Text("Use location") } }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 500)
    }
    private func search() {
        guard !searching else { return }
        searching = true; message = nil; matches = []
        let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { searching = false }
            do {
                matches = try await MapLocationStore.search(requested)
                if matches.isEmpty { message = "No city found. Try including the country." }
            } catch { message = "City lookup failed. Check your connection and try again." }
        }
    }
}
