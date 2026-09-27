import SwiftUI

// IDs stay stable when category names change. The two original IDs retain their
// old JSON representation so existing application files remain readable.
struct ApplicationKind: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }
    static let job = Self(rawValue: "Job")
    static let phd = Self(rawValue: "PhD")
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
    var icon: String {
        self == .job ? "briefcase" : self == .phd ? "graduationcap" : "tag"
    }
    var color: Color {
        if self == .job { return .teal }
        if self == .phd { return .indigo }
        let palette: [Color] = [.blue, .purple, .orange, .mint, .pink, .cyan, .green]
        let checksum = rawValue.utf8.reduce(0) { ($0 * 31 + Int($1)) % 65521 }
        return palette[checksum % palette.count]
    }
}
enum CategoryIcon: Codable, Equatable {
    case symbol(String)
    case emoji(String)
    static let symbols = ["briefcase", "graduationcap", "tag", "building.2", "flask", "books.vertical", "laptopcomputer", "stethoscope", "globe", "leaf", "paintbrush", "lightbulb", "heart", "star", "person.2", "wrench.and.screwdriver", "bolt", "paperplane"]
    static func symbolLabel(_ name: String) -> String {
        let labels = ["briefcase": "Briefcase", "graduationcap": "Academic cap", "tag": "Tag", "building.2": "Building", "flask": "Research", "books.vertical": "Books", "laptopcomputer": "Computer", "stethoscope": "Medicine", "globe": "Globe", "leaf": "Nature", "paintbrush": "Design", "lightbulb": "Idea", "heart": "Heart", "star": "Star", "person.2": "Team", "wrench.and.screwdriver": "Tools", "bolt": "Energy", "paperplane": "Application"]
        return labels[name] ?? "Symbol"
    }
    static func isEmoji(_ text: String) -> Bool {
        text.count == 1 && text.unicodeScalars.contains { $0.properties.isEmoji } &&
        (text.unicodeScalars.count > 1 || (text.unicodeScalars.first?.value ?? 0) > 127)
    }
    var isValid: Bool {
        switch self {
        case .symbol(let name): return Self.symbols.contains(name)
        case .emoji(let text): return Self.isEmoji(text)
        }
    }
}
struct CategoryIconView: View {
    let icon: CategoryIcon
    var body: some View {
        Group {
            switch icon {
            case .symbol(let name): Image(systemName: name)
            case .emoji(let emoji): Text(emoji)
            }
        }.accessibilityHidden(true)
    }
}
struct ApplicationCategory: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: CategoryIcon? = nil
    var effectiveIcon: CategoryIcon { icon ?? .symbol(kind.icon) }
    var kind: ApplicationKind { ApplicationKind(rawValue: id) }
    static let defaults = [Self(id: "Job", name: "Job"), Self(id: "PhD", name: "PhD")]
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func validate(_ categories: [Self], applications: [Application]) throws {
        guard !categories.isEmpty,
              categories.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }),
              Set(categories.map(\.id)).count == categories.count,
              Set(categories.map { normalizedName($0.name) }).count == categories.count else {
            throw AtlasBackup.Failure.invalid("Use unique category names of 1–40 characters, and keep at least one category.")
        }
        guard categories.allSatisfy({ $0.effectiveIcon.isValid }) else {
            throw AtlasBackup.Failure.invalid("Choose one emoji or a symbol from the icon picker.")
        }
        let ids = Set(categories.map(\.id))
        guard applications.allSatisfy({ ids.contains($0.kind.rawValue) }) else {
            throw AtlasBackup.Failure.invalid("Choose a remaining category for applications in a removed category.")
        }
    }
    static func inferred(for applications: [Application]) -> [Self] {
        var result = defaults
        for kind in Set(applications.map(\.kind)).sorted(by: { $0.rawValue < $1.rawValue }) where !result.contains(where: { $0.id == kind.rawValue }) {
            result.append(Self(id: kind.rawValue, name: kind.rawValue))
        }
        return result
    }
}
struct ApplicationDatabase: Codable {
    var version = 2
    var applications: [Application]
    var categories: [ApplicationCategory]
    static func read(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        if let old = try? decoder.decode([Application].self, from: data) {
            let migrated = Self(applications: old, categories: ApplicationCategory.inferred(for: old))
            try ApplicationCategory.validate(migrated.categories, applications: old)
            return migrated
        }
        let database = try decoder.decode(Self.self, from: data)
        guard database.version == 2 else { throw AtlasBackup.Failure.invalid("This application database was written by an unsupported version.") }
        try ApplicationCategory.validate(database.categories, applications: database.applications)
        return database
    }
}
