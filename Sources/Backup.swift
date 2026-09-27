import Foundation

struct AtlasBackup: Codable {
    var format = "application-atlas-backup"
    var version = 2
    var createdAt = Date()
    var applications: [Application]
    var attachments: [String: Data]
    var mapSettings: MapPreferences?
    var categories: [ApplicationCategory]? = ApplicationCategory.defaults
    var resolvedCategories: [ApplicationCategory] { categories ?? ApplicationCategory.inferred(for: applications) }

    static let maximumBytes = 512 * 1024 * 1024
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
    static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains(":") && !name.contains("\0")
    }
    func validate() throws {
        guard format == "application-atlas-backup", (version == 1 || version == 2) else { throw Failure.invalid("This is not a supported Application Atlas backup.") }
        if version == 2 && categories == nil { throw Failure.invalid("This backup is missing its categories.") }
        try ApplicationCategory.validate(resolvedCategories, applications: applications)
        guard Set(applications.map(\.id)).count == applications.count else { throw Failure.invalid("The backup contains duplicate application IDs.") }
        let referenced = Set(applications.flatMap(\.attachments).map(\.storedName))
        guard Set(attachments.keys) == referenced, referenced.allSatisfy(Self.validFilename),
              Set(referenced.map { $0.lowercased() }).count == referenced.count else {
            throw Failure.invalid("The backup has missing documents or invalid document filenames.")
        }
        guard attachments.values.reduce(0, { $0 + $1.count }) <= Self.maximumBytes else { throw Failure.invalid("This backup exceeds the 512 MB document limit.") }
        for application in applications {
            if let events = application.statusHistory, !events.isEmpty {
                guard events.last?.status == application.status, Set(events.map(\.id)).count == events.count else { throw Failure.invalid("The backup contains inconsistent journey steps.") }
            }
        }
        if let settings = mapSettings {
            for place in [settings.home] + Array(settings.cities.values) {
                guard place.latitude.isFinite, place.longitude.isFinite, (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else {
                    throw Failure.invalid("The backup contains an invalid map location.")
                }
            }
        }
    }
    static func capture(applications: [Application], directory: URL, categories: [ApplicationCategory]? = nil) throws -> AtlasBackup {
        var files: [String: Data] = [:]
        var total = 0
        for attachment in applications.flatMap(\.attachments) where files[attachment.storedName] == nil {
            guard validFilename(attachment.storedName) else { throw Failure.invalid("An attachment has an invalid storage filename.") }
            let url = directory.appendingPathComponent("Attachments").appendingPathComponent(attachment.storedName)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid("The attachment ‘\(attachment.name)’ is not a regular file.") }
            total += values.fileSize ?? 0
            guard total <= maximumBytes else { throw Failure.invalid("The documents exceed the 512 MB backup limit.") }
            files[attachment.storedName] = try Data(contentsOf: url)
        }
        let mapURL = directory.appendingPathComponent("map-settings.json")
        let settings = FileManager.default.fileExists(atPath: mapURL.path) ? try JSONDecoder().decode(MapPreferences.self, from: Data(contentsOf: mapURL)) : nil
        let savedCategories: [ApplicationCategory]
        if let categories { savedCategories = categories }
        else if FileManager.default.fileExists(atPath: directory.appendingPathComponent("applications.json").path) {
            savedCategories = try ApplicationDatabase.read(Data(contentsOf: directory.appendingPathComponent("applications.json"))).categories
        } else { savedCategories = ApplicationCategory.inferred(for: applications) }
        let backup = AtlasBackup(applications: applications, attachments: files, mapSettings: settings, categories: savedCategories)
        try backup.validate()
        return backup
    }
    func write(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    static func read(from url: URL) throws -> AtlasBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes * 2 else { throw Failure.invalid("The selected file is too large to be an Atlas backup.") }
        let backup = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try backup.validate()
        return backup
    }
}

enum ApplicationCSV {
    static func text(_ applications: [Application], categories: [ApplicationCategory] = ApplicationCategory.defaults, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        func date(_ date: Date?) -> String { date.map { formatter.string(from: $0) } ?? "" }
        func cell(_ value: String) -> String {
            // Keep user text literal when opened in spreadsheet software.
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = ["ID", "Role", "Organization", "Category", "Status", "Sent date", "Days awaiting reply", "Deadline", "Location", "URL", "Notes", "Documents", "Journey"]
        let rows = applications.map { application in
            [application.id.uuidString, application.role, application.organization, categories.first { $0.id == application.kind.rawValue }?.name ?? application.kind.rawValue,
             application.status.rawValue, date(application.sentDate), application.daysAwaitingReply(asOf: now, calendar: calendar).map(String.init) ?? "",
             date(application.deadline), application.location, application.url, application.notes,
             application.attachments.map(\.name).joined(separator: "; "),
             application.history.map { "\($0.status.rawValue) (\(date($0.date)))" }.joined(separator: " → ")]
        }
        return ([header] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
