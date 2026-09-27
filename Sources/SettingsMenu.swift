import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct PendingRestore: Identifiable {
    let id = UUID()
    let name: String
    let backup: AtlasBackup
}
struct SettingsMenu: View {
    @EnvironmentObject private var store: ApplicationStore
    @State private var busy = false
    @State private var showingAbout = false
    @State private var showingCategories = false
    @State private var pendingRestore: PendingRestore?
    @State private var message: String?
    @State private var outputURL: URL?
    var body: some View {
        Menu {
            Button("Manage categories…", systemImage: "tag") { showingCategories = true }.disabled(!store.canWrite)
            Divider()
            Button("Export all applications (CSV)…", systemImage: "tablecells") { exportCSV() }.disabled(!store.canWrite)
            Button("Create backup…", systemImage: "externaldrive.badge.plus") { createBackup() }.disabled(!store.canWrite)
            Button("Restore backup…", systemImage: "arrow.counterclockwise") { chooseBackup() }
            Divider()
            Button("Show local data", systemImage: "folder") { NSWorkspace.shared.open(store.directory) }
            Button("About & license…", systemImage: "info.circle") { showingAbout = true }
        } label: {
            if busy { ProgressView().controlSize(.small) }
            else { Label("Settings", systemImage: "gearshape") }
        }.disabled(busy).help(busy ? "Preparing your files…" : "Settings")
            .sheet(isPresented: $showingCategories) { CategoryManager().environmentObject(store) }
            .sheet(isPresented: $showingAbout) { AboutAtlas() }
            .sheet(item: $pendingRestore) { pending in
                RestoreConfirmation(pending: pending) {
                    do {
                        let recovery = try store.restore(pending.backup)
                        pendingRestore = nil
                        outputURL = recovery
                        message = "Restored \(pending.backup.applications.count) applications and \(pending.backup.attachments.count) documents. Your previous data is preserved in a recovery folder."
                    } catch {
                        pendingRestore = nil
                        outputURL = nil
                        message = "Restore failed: \(error.localizedDescription)"
                    }
                }
            }
            .alert("Application Atlas", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                if let outputURL { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([outputURL]); message = nil } }
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func saveDestination(name: String, type: UTType, explanation: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.message = explanation
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let dataPath = store.directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard !url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(dataPath) else {
            outputURL = nil; message = "Choose a location outside the app’s live data folder, such as Documents."
            return nil
        }
        return url
    }
    private var dateStamp: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    private func exportCSV() {
        guard let url = saveDestination(name: "Application Atlas \(dateStamp).csv", type: .commaSeparatedText,
                                        explanation: "Exports every application’s details and journey as a spreadsheet. Documents are included in backups instead.") else { return }
        let applications = store.applications, categories = store.categories
        busy = true; outputURL = nil
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ApplicationCSV.text(applications, categories: categories).write(to: url, atomically: true, encoding: .utf8)
                }.value
                outputURL = url; message = "Exported \(applications.count) applications."
            } catch { message = "Export failed: \(error.localizedDescription)" }
        }
    }
    private func createBackup() {
        guard let url = saveDestination(name: "Application Atlas Backup \(dateStamp).json", type: .json,
                                        explanation: "Saves all applications, journey steps, copied documents, categories, and map settings together in one backup file.") else { return }
        let applications = store.applications, directory = store.directory, categories = store.categories
        busy = true; outputURL = nil
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try AtlasBackup.capture(applications: applications, directory: directory, categories: categories).write(to: url)
                }.value
                outputURL = url; message = "Backup saved with \(applications.count) applications and their documents."
            } catch { message = "Backup failed: \(error.localizedDescription)" }
        }
    }
    private func chooseBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose an Application Atlas backup. You’ll review its contents before restoring."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; outputURL = nil
        Task {
            defer { busy = false }
            do {
                let backup = try await Task.detached(priority: .userInitiated) { try AtlasBackup.read(from: url) }.value
                pendingRestore = PendingRestore(name: url.lastPathComponent, backup: backup)
            } catch { message = "Could not open backup: \(error.localizedDescription)" }
        }
    }
}
private struct RestoreConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingRestore
    let onRestore: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Restore backup", systemImage: "arrow.counterclockwise").font(.title2.bold())
            Text(pending.name).font(.headline)
            Text("Created \(pending.backup.createdAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            Text("\(pending.backup.applications.count) applications · \(pending.backup.attachments.count) documents")
            Text("This replaces the current applications, documents, categories, and map settings. The current data will be preserved in a separate recovery folder.")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore backup") { onRestore() }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 470)
    }
}
private struct AboutAtlas: View {
    @State private var showingLicense = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 88, height: 88)
            }
            Text("Application Atlas").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                .font(.caption).foregroundStyle(.secondary)
            Text("A little progress, every day.").foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Text("Made with")
                Image(systemName: "heart.fill").foregroundStyle(.pink).accessibilityLabel("love")
                Text("by Jonas (2026)")
            }.font(.headline)
            Text("© 2026 Jonas · Open source").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Button("MIT license") { showingLicense = true }
                Link(destination: URL(string: "https://buymeacoffee.com/wagnerjon")!) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
            }
            Link("View source on GitHub", destination: URL(string: "https://github.com/WagnerJon/application-atlas")!)
            Text("Support is optional. All features are free.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }.padding(32).frame(width: 400)
            .sheet(isPresented: $showingLicense) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("MIT License").font(.title2.bold())
                    ScrollView {
                        Text(licenseText).font(.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack { Spacer(); Button("Done") { showingLicense = false }.keyboardShortcut(.defaultAction) }
                }.padding(24).frame(width: 540, height: 460)
            }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The MIT license is included in the source repository’s LICENSE file."
        }
        return text
    }
}
