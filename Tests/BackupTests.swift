import Foundation

@main struct BackupTests {
    @MainActor static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("atlas-backup-test-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let beforeDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 23, minute: 55))!
        let afterDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 23, minute: 55))!
        var application = Application()
        application.role = "Research, \"science\""
        application.organization = "=1+1"
        application.notes = "First line\nSecond line"
        application.status = .sent; application.sentDate = beforeDST
        assert(application.daysAwaitingReply(asOf: afterDST, calendar: calendar) == 1)
        assert(application.daysAwaitingReply(asOf: beforeDST, calendar: calendar) == 0)
        assert(application.daysAwaitingReply(asOf: beforeDST.addingTimeInterval(-100000), calendar: calendar) == 0)
        var withoutDate = application; withoutDate.sentDate = nil
        assert(withoutDate.daysAwaitingReply() == nil)
        var replied = application; replied.status = .interview
        assert(replied.daysAwaitingReply() == nil)
        var tomorrow = Application(); tomorrow.deadline = afterDST
        var today = Application(); today.deadline = beforeDST
        var overdue = Application(); overdue.deadline = calendar.date(byAdding: .day, value: -2, to: beforeDST)
        var older = Application(); older.deadline = calendar.date(byAdding: .day, value: -5, to: beforeDST)
        assert(tomorrow.daysTillDeadline(asOf: beforeDST, calendar: calendar) == 1)
        assert(today.daysTillDeadline(asOf: beforeDST, calendar: calendar) == 0)
        assert(overdue.daysTillDeadline(asOf: beforeDST, calendar: calendar) == -2)
        assert(Application().daysTillDeadline(asOf: beforeDST, calendar: calendar) == nil)
        let deadlines = Application.orderedByDeadline([older, tomorrow, Application(), overdue, today], asOf: beforeDST, calendar: calendar)
        assert(deadlines.map(\.id) == [today.id, tomorrow.id, overdue.id, older.id])
        assert(Application.orderedByDeadline([today, tomorrow], asOf: afterDST, calendar: calendar).map(\.id) == [tomorrow.id, today.id])
        print("PASS: deadline filtering, nearest-first ordering, overdue ordering, calendar days and DST")
        let csv = ApplicationCSV.text([application], now: afterDST, calendar: calendar)
        assert(csv.contains("\"Research, \"\"science\"\"\""))
        assert(csv.contains("\"'=1+1\""))
        assert(csv.contains("\"First line\nSecond line\""))
        assert(csv.contains("\"2026-03-28\",\"1\""))
        assert(ApplicationCSV.text([]).contains("Days awaiting reply"))

        let store = ApplicationStore(directory: root.appendingPathComponent("Live"))
        let original = root.appendingPathComponent("letter.txt")
        try Data("Cover letter – original version".utf8).write(to: original)
        let attachment = try store.importAttachment(original)
        application.attachments = [attachment]
        assert(store.save(application))
        let map = MapLocationStore(directory: store.directory)
        let paris = MapPlace(name: "Paris", latitude: 48.85, longitude: 2.35)
        assert(map.setHome(paris))
        let backup = try AtlasBackup.capture(applications: store.applications, directory: store.directory)
        let archiveURL = root.appendingPathComponent("backup.json")
        try backup.write(to: archiveURL)
        let loaded = try AtlasBackup.read(from: archiveURL)
        assert(loaded.applications.count == 1 && loaded.attachments.count == 1 && loaded.mapSettings?.home == paris)

        var changed = store.applications[0]
        changed.addStep(.rejected, on: afterDST)
        assert(store.save(changed))
        var additional = Application(); additional.role = "Another role"; additional.organization = "Another company"
        assert(store.save(additional))
        assert(map.setHome(.heidelberg))
        let recovery = try store.restore(loaded)
        assert(store.applications.count == 1 && store.applications[0].status == .sent)
        let document = try Data(contentsOf: store.fileURL(attachment))
        assert(document == Data("Cover letter – original version".utf8))
        assert(MapLocationStore(directory: store.directory).preferences.home == paris)
        assert(ApplicationStore(directory: recovery).applications.count == 2)
        assert(ApplicationStore(directory: recovery).applications.first { $0.id == application.id }?.status == .rejected)
        assert(ApplicationStore(directory: store.directory).applications[0].history.count == 1)

        func rejects(_ action: () throws -> Void) {
            do { try action(); assertionFailure("Invalid backup was accepted") } catch { }
        }
        var unsupported = loaded; unsupported.version = 99
        rejects { try unsupported.validate() }
        var missing = loaded; missing.attachments = [:]
        rejects { try missing.validate() }
        var duplicate = loaded; duplicate.applications.append(duplicate.applications[0])
        rejects { try duplicate.validate() }
        var unsafe = loaded
        unsafe.applications[0].attachments[0].storedName = "../outside.txt"
        unsafe.attachments = ["../outside.txt": Data("bad".utf8)]
        let revision = store.restoreRevision
        rejects { _ = try store.restore(unsafe) }
        assert(store.restoreRevision == revision && store.applications.count == 1)
        assert(!manager.fileExists(atPath: root.appendingPathComponent("outside.txt").path))
        var badMap = loaded; badMap.mapSettings?.home.latitude = 999
        rejects { try badMap.validate() }
        try manager.removeItem(at: store.fileURL(attachment))
        rejects { _ = try AtlasBackup.capture(applications: store.applications, directory: store.directory) }
        try manager.createSymbolicLink(at: store.fileURL(attachment), withDestinationURL: original)
        rejects { _ = try AtlasBackup.capture(applications: store.applications, directory: store.directory) }
        let empty = AtlasBackup(applications: [], attachments: [:], mapSettings: nil)
        _ = try store.restore(empty)
        assert(store.applications.isEmpty)
        assert(MapLocationStore(directory: store.directory).preferences.home == .heidelberg)
        print("PASS: waiting-day calendar/DST cases, CSV escaping, complete backup round trip, atomic restore/recovery, and invalid/missing/unsafe backup rejection")
    }
}
