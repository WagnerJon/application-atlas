import Foundation
import AppKit

@main struct CategoryTests {
    @MainActor static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("atlas-categories-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let live = root.appendingPathComponent("Live")
        try manager.createDirectory(at: live, withIntermediateDirectories: true)
        var job = Application(); job.role = "Engineer"; job.organization = "Example"; job.kind = .job
        job.addStep(.sent, on: Date())
        var phd = Application(); phd.role = "Doctoral researcher"; phd.organization = "University"; phd.kind = .phd
        let oldData = try JSONEncoder().encode([job, phd])
        try oldData.write(to: live.appendingPathComponent("applications.json"))
        let store = ApplicationStore(directory: live)
        assert(store.error == nil && store.categories == ApplicationCategory.defaults)
        assert(store.applications.count == 2 && store.applications[0].kind == .job)
        let untouched = try Data(contentsOf: store.database)
        assert(untouched == oldData, "Loading legacy data should not rewrite it")

        let fellowship = ApplicationCategory(id: UUID().uuidString, name: "Fellowship")
        let internship = ApplicationCategory(id: UUID().uuidString, name: "Internship")
        let categories = ApplicationCategory.defaults + [fellowship, internship]
        assert(store.updateCategories(categories))
        var fellow = Application(); fellow.role = "Research fellow"; fellow.organization = "Institute"; fellow.kind = fellowship.kind
        assert(store.save(fellow))
        assert(ApplicationStore(directory: live).categories == categories)
        assert(ApplicationStore(directory: live).applications.last?.kind == fellowship.kind)
        var renamed = categories; renamed[0].name = "Employment"; renamed[2].name = "Research fellowship"
        let previousHistory = store.applications[0].history.map(\.id)
        assert(store.updateCategories(renamed))
        assert(store.applications[0].kind == .job && store.applications[0].history.map(\.id) == previousHistory)
        assert(store.categoryName(.job) == "Employment")
        let graph = ApplicationPipeline(store.applications, categories: store.categories)
        assert(graph.nodes.contains { $0.column == 1 && $0.label == "Employment" && $0.count == 1 })
        assert(graph.nodes.contains { $0.column == 1 && $0.label == "Research fellowship" && $0.count == 1 })
        assert(graph.nodes.filter { $0.column == 1 }.reduce(0) { $0 + $1.count } == 3)
        let csv = ApplicationCSV.text(store.applications, categories: store.categories)
        assert(csv.contains("Research fellowship") && !csv.contains(fellowship.id))
        let beforeInvalid = try Data(contentsOf: store.database)
        assert(!store.updateCategories([]))
        var duplicate = renamed; duplicate[3].name = "  EMPLOYMENT  "
        assert(!store.updateCategories(duplicate))
        assert(!store.updateCategories(Array(renamed.dropFirst())))
        let afterInvalid = try Data(contentsOf: store.database)
        assert(afterInvalid == beforeInvalid, "Invalid category changes must not modify data")
        assert(store.updateCategories(Array(renamed.dropFirst()), reassignments: ["Job": fellowship.id]))
        assert(store.applications[0].kind == fellowship.kind)
        assert(store.applications[0].history.map(\.id) == previousHistory)
        assert(store.applications.count == 3)
        assert(!store.save(job), "An old editor cannot silently revive a removed category")

        let backup = try AtlasBackup.capture(applications: store.applications, directory: live, categories: store.categories)
        let backupURL = root.appendingPathComponent("categories-backup.json")
        try backup.write(to: backupURL)
        let restoredBackup = try AtlasBackup.read(from: backupURL)
        let destination = ApplicationStore(directory: root.appendingPathComponent("Restored"))
        _ = try destination.restore(restoredBackup)
        assert(destination.categories == store.categories && destination.categories.contains(internship))
        assert(destination.applications[0].kind == fellowship.kind)
        assert(ApplicationStore(directory: destination.directory).categories == store.categories)

        // Old v1 backups had no categories field and remain importable.
        var oldBackup = AtlasBackup(applications: [job, phd], attachments: [:], mapSettings: nil)
        oldBackup.version = 1; oldBackup.categories = nil
        try oldBackup.write(to: root.appendingPathComponent("old-backup.json"))
        let loadedOld = try AtlasBackup.read(from: root.appendingPathComponent("old-backup.json"))
        assert(loadedOld.resolvedCategories == ApplicationCategory.defaults)
        _ = try destination.restore(loadedOld)
        assert(destination.categories == ApplicationCategory.defaults)
        assert(destination.applications[0].kind == .job)

        // Icon customization is optional for old data, and travels with categories.
        let oldCategory = try JSONDecoder().decode(ApplicationCategory.self, from: Data(#"{"id":"PhD","name":"PhD"}"#.utf8))
        assert(oldCategory.icon == nil && oldCategory.effectiveIcon == .symbol("graduationcap"))
        var iconCategories = destination.categories
        iconCategories[0].icon = .emoji("👩🏽‍🔬")
        iconCategories[1].icon = .symbol("books.vertical")
        assert(destination.updateCategories(iconCategories))
        let iconReloaded = ApplicationStore(directory: destination.directory)
        assert(iconReloaded.categoryIcon(.job) == .emoji("👩🏽‍🔬"))
        assert(iconReloaded.categoryIcon(.phd) == .symbol("books.vertical"))
        let iconGraph = ApplicationPipeline(iconReloaded.applications, categories: iconReloaded.categories)
        assert(iconGraph.nodes.first { $0.id == "category:Job" }?.icon == .emoji("👩🏽‍🔬"))
        let iconBackup = try AtlasBackup.capture(applications: iconReloaded.applications, directory: destination.directory, categories: iconReloaded.categories)
        let iconBackupURL = root.appendingPathComponent("icon-backup.json")
        try iconBackup.write(to: iconBackupURL)
        let iconRestore = ApplicationStore(directory: root.appendingPathComponent("IconRestore"))
        _ = try iconRestore.restore(AtlasBackup.read(from: iconBackupURL))
        assert(iconRestore.categories == iconReloaded.categories)
        assert(CategoryIcon.isEmoji("🇩🇪") && CategoryIcon.isEmoji("1️⃣") && CategoryIcon.isEmoji("🎓"))
        assert(!CategoryIcon.isEmoji("1") && !CategoryIcon.isEmoji("text") && !CategoryIcon.isEmoji("🎓🌎"))
        for name in CategoryIcon.symbols { assert(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Missing system symbol: \(name)") }
        var invalidIcons = iconCategories; invalidIcons[0].icon = .emoji("not an emoji")
        assert(!destination.updateCategories(invalidIcons))
        invalidIcons[0].icon = .symbol("invented.icon")
        assert(!destination.updateCategories(invalidIcons))
        iconCategories[0].icon = nil
        assert(destination.updateCategories(iconCategories))
        assert(destination.categoryIcon(.job) == .symbol("briefcase"))

        let many = (0..<12).map { ApplicationCategory(id: "category-\($0)", name: "Category \($0)") }
        let records = many.map { category in var record = Application(); record.kind = category.kind; return record }
        let largeGraph = ApplicationPipeline(records, categories: many)
        assert(largeGraph.nodes.filter { $0.column == 1 }.count == 12)
        assert(largeGraph.drawingHeight > 410)
        print("PASS: legacy category migration, custom categories/rename/reassignment, validation, dynamic Sankey/CSV labels, backup compatibility, and emoji/symbol validation/persistence/restore")
    }
}
