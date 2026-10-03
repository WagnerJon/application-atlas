import SwiftUI
import AppKit
import Darwin

enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Draft", sent = "Awaiting response", response = "Response received", interview = "Interview", offer = "Offer", rejected = "Rejected", withdrawn = "Withdrawn"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .draft: .gray
        case .sent: .blue
        case .response: .cyan
        case .interview: .orange
        case .offer: .green
        case .rejected: .pink
        case .withdrawn: .secondary
        }
    }
    var isResponse: Bool { [.response, .interview, .offer, .rejected].contains(self) }
}
struct Attachment: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var storedName: String
}
struct StatusEvent: Codable, Identifiable {
    var id = UUID()
    var status: ApplicationStatus
    // Unknown for records created before status history was supported.
    var date: Date?
}
struct Application: Codable, Identifiable {
    var id = UUID()
    var role = ""
    var organization = ""
    var kind: ApplicationKind = .job
    var status: ApplicationStatus = .draft
    var sentDate: Date? = nil
    var deadline: Date? = nil
    var location = ""
    var url = ""
    var notes = ""
    var attachments: [Attachment] = []
    var createdAt = Date()
    var statusHistory: [StatusEvent]? = nil
    var history: [StatusEvent] {
        if let events = statusHistory, !events.isEmpty { return events }
        return [StatusEvent(id: id, status: status, date: nil)]
    }
    func daysAwaitingReply(asOf now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard status == .sent, let sentDate else { return nil }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: sentDate), to: calendar.startOfDay(for: now)).day ?? 0)
    }
    func daysTillDeadline(asOf now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let deadline else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day
    }
    static func orderedByDeadline(_ applications: [Application], asOf now: Date = Date(), calendar: Calendar = .current) -> [Application] {
        applications.filter { $0.deadline != nil }.sorted { lhs, rhs in
            let left = lhs.daysTillDeadline(asOf: now, calendar: calendar)!
            let right = rhs.daysTillDeadline(asOf: now, calendar: calendar)!
            if (left < 0) != (right < 0) { return left >= 0 }
            if left != right { return left < 0 ? left > right : left < right }
            if lhs.deadline != rhs.deadline { return lhs.deadline! < rhs.deadline! }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
    func reached(_ status: ApplicationStatus) -> Bool {
        self.status == status || history.contains { $0.status == status }
    }
    mutating func updateStep(id: UUID, status: ApplicationStatus, date: Date?) {
        var events = history
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let previous = events[index]
        events[index].status = status
        events[index].date = date
        statusHistory = events
        self.status = events.last!.status
        // Keep the sent date aligned when this is the step it was derived from.
        if previous.status == .sent && status == .sent && (sentDate == previous.date || sentDate == nil) {
            sentDate = date
        }
    }
    mutating func addStep(_ status: ApplicationStatus, on date: Date) {
        var events = history
        events.append(StatusEvent(status: status, date: date))
        statusHistory = events
        self.status = status
        if status != .draft && sentDate == nil { sentDate = date }
    }
}
@MainActor final class ApplicationStore: ObservableObject {
    @Published private(set) var applications: [Application] = []
    @Published private(set) var categories = ApplicationCategory.defaults
    @Published var error: String?
    @Published private(set) var restoreRevision = UUID()
    @Published var showingFirstOfferSupport = false
    private let preferences: UserDefaults
    private let firstOfferKey = "firstOfferSupportShown"
    private(set) var canWrite = true
    let directory: URL
    var database: URL { directory.appendingPathComponent("applications.json") }
    var attachmentDirectory: URL { directory.appendingPathComponent("Attachments", isDirectory: true) }
    init(directory: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ApplicationAtlas", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: database.path) {
                let loaded = try ApplicationDatabase.read(Data(contentsOf: database))
                applications = loaded.applications
                categories = loaded.categories
                if applications.contains(where: { $0.reached(.offer) }) { preferences.set(true, forKey: firstOfferKey) }
            }
        } catch { canWrite = false; self.error = "Could not load your data. Existing files have been preserved. \(error.localizedDescription)" }
    }
    @discardableResult func save(_ application: Application) -> Bool {
        var next = applications
        var updated = application
        if let index = next.firstIndex(where: { $0.id == application.id }) {
            // Preserve history even when a caller changes only the current status.
            if updated.statusHistory == nil { updated.statusHistory = next[index].history }
            if updated.history.last?.status != updated.status {
                updated.statusHistory = updated.history + [StatusEvent(status: updated.status, date: Date())]
            }
            next[index] = updated
        } else {
            if updated.statusHistory == nil {
                updated.statusHistory = [StatusEvent(status: updated.status, date: updated.status == .sent ? updated.sentDate : Date())]
            }
            next.append(updated)
        }
        let firstOffer = updated.reached(.offer) && !applications.contains(where: { $0.reached(.offer) }) && !preferences.bool(forKey: firstOfferKey)
        guard persist(next) else { return false }
        if firstOffer {
            preferences.set(true, forKey: firstOfferKey)
            showingFirstOfferSupport = true
        }
        return true
    }
    // Build and validate a complete replacement before touching the live directory.
    // The old directory is retained beside it as a recovery copy.
    @discardableResult func restore(_ backup: AtlasBackup) throws -> URL {
        try backup.validate()
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".atlas-restore-\(UUID().uuidString)", isDirectory: true)
        let recovery = parent.appendingPathComponent("\(directory.lastPathComponent)-before-restore-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        var swapped = false
        defer { if !swapped { try? manager.removeItem(at: staging) } }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ApplicationDatabase(applications: backup.applications, categories: backup.resolvedCategories)).write(to: staging.appendingPathComponent("applications.json"), options: .atomic)
        for (name, data) in backup.attachments {
            try data.write(to: staging.appendingPathComponent("Attachments").appendingPathComponent(name), options: .atomic)
        }
        if let map = backup.mapSettings { try encoder.encode(map).write(to: staging.appendingPathComponent("map-settings.json"), options: .atomic) }
        guard renamex_np(staging.path, directory.path, UInt32(RENAME_SWAP)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Could not replace the application data. Your current data is unchanged."])
        }
        swapped = true
        // After the atomic swap, staging holds the complete previous directory.
        var recoveryURL = recovery
        do { try manager.moveItem(at: staging, to: recovery) }
        catch { recoveryURL = staging }
        applications = backup.applications
        if applications.contains(where: { $0.reached(.offer) }) { preferences.set(true, forKey: firstOfferKey) }
        showingFirstOfferSupport = false
        categories = backup.resolvedCategories
        canWrite = true
        error = nil
        restoreRevision = UUID()
        return recoveryURL
    }
    @discardableResult func delete(_ application: Application) -> Bool {
        guard persist(applications.filter { $0.id != application.id }) else { return false }
        for attachment in application.attachments { try? FileManager.default.removeItem(at: fileURL(attachment)) }
        return true
    }
    func categoryIcon(_ kind: ApplicationKind) -> CategoryIcon {
        categories.first { $0.id == kind.rawValue }?.effectiveIcon ?? .symbol(kind.icon)
    }
    func categoryName(_ kind: ApplicationKind) -> String {
        categories.first { $0.id == kind.rawValue }?.name ?? kind.rawValue
    }
    @discardableResult func updateCategories(_ categories: [ApplicationCategory], reassignments: [String: String] = [:]) -> Bool {
        let normalized = categories.map { ApplicationCategory(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), icon: $0.icon) }
        let updated = applications.map { application in
            var result = application
            if let target = reassignments[application.kind.rawValue] { result.kind = ApplicationKind(rawValue: target) }
            return result
        }
        return persist(updated, categories: normalized)
    }
    private func persist(_ next: [Application], categories newCategories: [ApplicationCategory]? = nil) -> Bool {
        guard canWrite else { error = "Saving is disabled because the existing data could not be loaded. Resolve the storage issue and reopen the app."; return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let categories = newCategories ?? self.categories
            try ApplicationCategory.validate(categories, applications: next)
            try encoder.encode(ApplicationDatabase(applications: next, categories: categories)).write(to: database, options: .atomic)
            applications = next
            self.categories = categories
            return true
        } catch { self.error = "Could not save: \(error.localizedDescription)"; return false }
    }
    func importAttachment(_ url: URL) throws -> Attachment {
        let stored = UUID().uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
        try FileManager.default.copyItem(at: url, to: attachmentDirectory.appendingPathComponent(stored))
        return Attachment(name: url.lastPathComponent, storedName: stored)
    }
    func fileURL(_ attachment: Attachment) -> URL { attachmentDirectory.appendingPathComponent(attachment.storedName) }
    func removeUnused(_ attachments: [Attachment]) {
        let used = Set(applications.flatMap(\.attachments).map(\.storedName))
        for file in attachments where !used.contains(file.storedName) { try? FileManager.default.removeItem(at: fileURL(file)) }
    }
    func open(_ attachment: Attachment) {
        if !NSWorkspace.shared.open(fileURL(attachment)) { error = "This attachment could not be opened. It may have been moved or removed." }
    }
}

struct ApplicationSort {
    enum Field { case status, sent }
    var field: Field = .sent
    var ascending = false

    mutating func select(_ field: Field) {
        if self.field == field { ascending.toggle() }
        else { self.field = field; ascending = field == .status }
    }
    func ordered(_ applications: [Application]) -> [Application] {
        applications.sorted { lhs, rhs in
            if field == .status {
                let left = ApplicationStatus.allCases.firstIndex(of: lhs.status)!
                let right = ApplicationStatus.allCases.firstIndex(of: rhs.status)!
                if left != right { return ascending ? left < right : left > right }
            }
            // Undated applications always follow dated applications, in either direction.
            switch (lhs.sentDate, rhs.sentDate) {
            case let (left?, right?) where left != right:
                let chronological = field == .sent ? ascending : false
                return chronological ? left < right : left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
