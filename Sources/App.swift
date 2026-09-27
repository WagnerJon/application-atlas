import SwiftUI
import AppKit

@main struct AtlasApp: App {
    @StateObject private var store = ApplicationStore()
    var body: some Scene {
        WindowGroup("Application Atlas") {
            ContentView().environmentObject(store).frame(minWidth: 1040, minHeight: 720)
                .tint(.teal)
        }.defaultSize(width: 1220, height: 850)
            .commands { CommandGroup(replacing: .newItem) { Button("New application") { NotificationCenter.default.post(name: .newApplication, object: nil) }.keyboardShortcut("n") } }
    }
}
extension Notification.Name { static let newApplication = Notification.Name("newApplication") }
enum Page: Hashable {
    case dashboard, all, category(String), map
}
struct ContentView: View {
    @EnvironmentObject var store: ApplicationStore
    @State private var page: Page? = .dashboard
    @State private var query = ""
    @State private var applicationSort = ApplicationSort()
    @State private var statusFilter: ApplicationStatus?
    @State private var journeyFilter: ApplicationStatus?
    @State private var editing: Application?
    @State private var deleting: Application?
    var filtered: [Application] {
        applicationSort.ordered(store.applications.filter { application in
            matchesCategory(application) &&
            (statusFilter == nil || application.status == statusFilter) &&
            (journeyFilter == nil || application.reached(journeyFilter!)) &&
            (query.isEmpty || "\(application.role) \(application.organization) \(application.location)".localizedCaseInsensitiveContains(query))
        })
    }
    private func matchesCategory(_ application: Application) -> Bool {
        if case .category(let id) = page { return application.kind.rawValue == id }
        return true
    }
    private var pageTitle: String {
        switch page {
        case .dashboard: return "Make your next move."
        case .category(let id): return store.categoryName(ApplicationKind(rawValue: id))
        case .map: return "Map"
        default: return "All applications"
        }
    }
    private func newApplication() {
        var application = Application()
        if case .category(let id) = page { application.kind = ApplicationKind(rawValue: id) }
        else { application.kind = store.categories.first?.kind ?? .job }
        editing = application
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let icon = NSImage(contentsOf: iconURL) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "globe").font(.system(size: 29)).foregroundStyle(.teal)
                    }
                    VStack(alignment: .leading, spacing: 2) { Text("ATLAS").font(.system(size: 18, weight: .bold, design: .rounded)); Text("Your next chapter").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 20).padding(.top, 25)
                List(selection: $page) {
                    Label("Overview", systemImage: "square.grid.2x2").padding(.vertical, 7).tag(Page.dashboard)
                    Label("All applications", systemImage: "tray.full").padding(.vertical, 7).tag(Page.all)
                    ForEach(store.categories) { category in
                        Label { Text(category.name) } icon: { CategoryIconView(icon: category.effectiveIcon) }
                            .lineLimit(1).help(category.name).padding(.vertical, 7).tag(Page.category(category.id))
                    }
                    Label("Map", systemImage: "map").padding(.vertical, 7).tag(Page.map)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("A little progress, every day.", systemImage: "sparkle").font(.caption.weight(.medium))
                    Text("Your applications and documents, together on this Mac.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            if page == .map {
                ApplicationMapView(applications: store.applications, directory: store.directory) { editing = $0 }.id(store.restoreRevision)
            } else {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(pageTitle).font(.system(size: 30, weight: .bold, design: .rounded))
                            Text(page == .dashboard ? "A clear view of where you are, and what’s ahead." : "Every opportunity has a place here.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { newApplication() } label: { Label("New application", systemImage: "plus").padding(.vertical, 5) }.buttonStyle(.borderedProminent)
                    }
                    if page == .dashboard {
                        HStack(spacing: 14) {
                            metric("APPLICATIONS", value: store.applications.count, icon: "paperplane", color: .teal)
                            metric("AWAITING REPLY", value: store.applications.filter { $0.status == .sent }.count, icon: "clock", color: .blue)
                            metric("RESPONSES", value: store.applications.filter { $0.status.isResponse }.count, icon: "bubble.left.and.bubble.right", color: .indigo)
                            metric("OFFERS", value: store.applications.filter { $0.status == .offer }.count, icon: "star", color: .green)
                        }
                        SankeyView(applications: store.applications, categories: store.categories, selectedStatus: journeyFilter) { status in
                            journeyFilter = journeyFilter == status ? nil : status
                            statusFilter = nil
                            query = ""
                            withAnimation { proxy.scrollTo("application-list", anchor: .top) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(page == .dashboard ? "Your applications" : "Application ledger").font(.title3.weight(.semibold))
                            Text("\(filtered.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                            Spacer()
                            Picker("Status", selection: $statusFilter) {
                                Text("All statuses").tag(nil as ApplicationStatus?)
                                ForEach(ApplicationStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                            }.labelsHidden().frame(width: 175)
                                .onChange(of: statusFilter) { _, value in if value != nil { journeyFilter = nil } }
                            TextField("Search applications", text: $query).textFieldStyle(.roundedBorder).frame(width: 190)
                        }
                        if let journeyFilter {
                            HStack {
                                Label("Reached: \(journeyFilter.rawValue)", systemImage: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(journeyFilter.color)
                                Text("Includes earlier steps").foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear filter") { self.journeyFilter = nil; statusFilter = nil; query = "" }
                            }.font(.caption)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView(store.applications.isEmpty ? "Room for your next opportunity" : "No matching applications", systemImage: "tray", description: Text(store.applications.isEmpty ? "Add a job or PhD application, record the date, and keep your letters close." : "Try another search or status filter."))
                        } else {
                            HStack { Text("OPPORTUNITY"); Spacer(); sortHeader("STATUS", field: .status).frame(width: 150, alignment: .leading); sortHeader("SENT", field: .sent).frame(width: 92, alignment: .leading); Color.clear.frame(width: 30, height: 1) }.font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 12)
                            LazyVStack(spacing: 0) { ForEach(filtered) { application in
                                applicationRow(application)
                                if application.id != filtered.last?.id { Divider().padding(.leading, 58) }
                            } }
                        }
                    }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 16)).id("application-list")
                    Text("APPLICATION DATA SAVED ON THIS MAC").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }.padding(30)
            }.background(Color(nsColor: .windowBackgroundColor))
            }
            }
        }
        .toolbar { ToolbarItem(placement: .primaryAction) { SettingsMenu() } }
        .onChange(of: store.restoreRevision) { _, _ in
            editing = nil; deleting = nil; page = .dashboard; query = ""; statusFilter = nil; journeyFilter = nil
        }
        .onChange(of: store.categories) { _, categories in
            if case .category(let id) = page, !categories.contains(where: { $0.id == id }) { page = .all }
        }
        .sheet(item: $editing) { application in ApplicationEditor(application: application, isNew: !store.applications.contains { $0.id == application.id }).environmentObject(store) }
        .onReceive(NotificationCenter.default.publisher(for: .newApplication)) { _ in newApplication() }
        .alert("Storage issue", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("Delete this application?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let application = deleting { store.delete(application) }; deleting = nil }
        } message: { Text("This removes the application and its saved document copies. Your original files are unaffected.") }
    }
    private func sortHeader(_ title: String, field: ApplicationSort.Field) -> some View {
        Button { applicationSort.select(field) } label: {
            HStack(spacing: 5) {
                Text(title)
                if applicationSort.field == field {
                    Image(systemName: applicationSort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(applicationSort.field == field ? Color.teal : Color.secondary)
            .help(field == .status ? "Sort by application stage; click again to reverse" : "Sort by sent date; click again to reverse. Unsent applications appear last.")
            .accessibilityLabel(field == .status ? "Sort by status" : "Sort by sent date")
            .accessibilityValue(applicationSort.field == field ? (applicationSort.ascending ? "Ascending" : "Descending") : "Not sorted")
    }
    func metric(_ label: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(color) }
            Text("\(value)").font(.system(size: 34, weight: .semibold, design: .rounded))
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    func applicationRow(_ application: Application) -> some View {
        HStack(spacing: 12) {
            Button { editing = application } label: {
                HStack(spacing: 12) {
                    CategoryIconView(icon: store.categoryIcon(application.kind)).font(.system(size: 18)).foregroundStyle(application.kind.color).frame(width: 36, height: 40).background(application.kind.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(application.role).fontWeight(.medium).lineLimit(1)
                        HStack(spacing: 7) { Text(application.organization).lineLimit(1); if !application.attachments.isEmpty { Image(systemName: "paperclip"); Text("\(application.attachments.count)") } }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Circle().fill(application.status.color).frame(width: 6, height: 6); Text(application.status.rawValue).font(.caption) }
                        if application.status == .sent && application.sentDate != nil {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                if let days = application.daysAwaitingReply(asOf: context.date) {
                                    Text(days == 0 ? "Sent today" : "Waiting \(days) \(days == 1 ? "day" : "days")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.frame(width: 150, alignment: .leading)
                    Text(application.sentDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not sent").font(.caption).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button("Edit details") { editing = application }
                if let url = URL(string: application.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { Button("Open opportunity") { NSWorkspace.shared.open(url) } }
                Divider()
                Button("Delete application", role: .destructive) { deleting = application }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 30)
        }.padding(.horizontal, 12).padding(.vertical, 13)
    }
}
