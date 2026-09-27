import SwiftUI
import AppKit

struct ApplicationEditor: View {
    @EnvironmentObject var store: ApplicationStore
    @Environment(\.dismiss) var dismiss
    @State var application: Application
    @State private var imported: [Attachment] = []
    @State private var removed: [Attachment] = []
    @State private var committed = false
    @State private var importError: String?
    @State private var nextStatus: ApplicationStatus = .response
    @State private var stepDate = Date()
    @State private var editingStep: StatusEvent?
    var isNew: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "A new possibility" : "Application details").font(.title2.bold())
                    Text(isNew ? "Keep the details. Focus on what’s next." : application.organization).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save application") {
                    application.role = application.role.trimmingCharacters(in: .whitespacesAndNewlines)
                    application.organization = application.organization.trimmingCharacters(in: .whitespacesAndNewlines)
                    if store.save(application) { committed = true; store.removeUnused(removed); dismiss() }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(application.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || application.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canWrite || !store.categories.contains(where: { $0.kind == application.kind }))
            }.padding(24)
            Divider()
            Form {
                Section("Opportunity") {
                    TextField("Role / PhD project", text: $application.role)
                    TextField("Company / university", text: $application.organization)
                    Picker("Category", selection: $application.kind) {
                        ForEach(store.categories) { category in
                            Label { Text(category.name) } icon: { CategoryIconView(icon: category.effectiveIcon) }.tag(category.kind)
                        }
                        if !store.categories.contains(where: { $0.kind == application.kind }) {
                            Text("Choose a category").tag(application.kind)
                        }
                    }
                    TextField("Location (city, country)", text: $application.location)
                    TextField("Opportunity URL", text: $application.url)
                }
                Section("Progress & dates") {
                    if isNew && application.statusHistory == nil {
                        Picker("Initial status", selection: $application.status) { ForEach(ApplicationStatus.allCases) { Text($0.rawValue).tag($0) } }
                            .onChange(of: application.status) { _, status in
                                if status != .draft && application.sentDate == nil { application.sentDate = Date() }
                            }
                    } else {
                        LabeledContent("Current status", value: application.status.rawValue)
                    }
                    Toggle("Application has been sent", isOn: Binding(get: { application.sentDate != nil }, set: { application.sentDate = $0 ? Date() : nil }))
                    if application.sentDate != nil {
                        DatePicker("Sent on", selection: Binding(get: { application.sentDate ?? Date() }, set: { application.sentDate = $0 }), displayedComponents: .date)
                    }
                    Toggle("Add a deadline", isOn: Binding(get: { application.deadline != nil }, set: { application.deadline = $0 ? Date() : nil }))
                    if application.deadline != nil {
                        DatePicker("Deadline", selection: Binding(get: { application.deadline ?? Date() }, set: { application.deadline = $0 }), displayedComponents: .date)
                    }
                }
                Section("Application journey") {
                    ForEach(application.history) { event in
                        Button { editingStep = event } label: {
                            HStack {
                                Circle().fill(event.status.color).frame(width: 8, height: 8)
                                Text(event.status.rawValue)
                                Spacer()
                                Text(event.date?.formatted(date: .abbreviated, time: .omitted) ?? "Date not recorded")
                                    .font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help("Edit this step’s status and date")
                            .accessibilityLabel("Edit step: \(event.status.rawValue), \(event.date?.formatted(date: .abbreviated, time: .omitted) ?? "date not recorded")")
                    }
                    Picker("Next step", selection: $nextStatus) {
                        ForEach(ApplicationStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Step date", selection: $stepDate, displayedComponents: .date)
                    Button {
                        application.addStep(nextStatus, on: stepDate)
                    } label: { Label("Add step", systemImage: "plus.circle") }
                    Text("Click a step to edit its status or date, or add another step below. Steps stay in their recorded order. Save application to keep your changes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(application.attachments) { file in
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.teal)
                            Text(file.name).lineLimit(1)
                            Spacer()
                            Button("Open") { store.open(file) }
                            Button { removed.append(file); application.attachments.removeAll { $0.id == file.id } } label: { Image(systemName: "minus.circle") }.help("Remove attachment")
                        }
                    }
                    Button { chooseFiles() } label: { Label("Attach cover letter or other files…", systemImage: "paperclip") }
                    Text("Files are copied into the app’s local storage, so your submitted versions stay with each application.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Documents") }
                Section("Notes") {
                    TextEditor(text: $application.notes).font(.body).frame(minHeight: 100)
                }
            }.formStyle(.grouped)
        }.frame(width: 670, height: 760)
            .sheet(item: $editingStep) { event in
                StepEditor(event: event) { updated in
                    application.updateStep(id: updated.id, status: updated.status, date: updated.date)
                }
            }
            .onDisappear { if !committed { store.removeUnused(imported) } }
            .alert("Unable to attach file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) { Button("OK") { importError = nil } } message: { Text(importError ?? "") }
    }
    private func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { let file = try store.importAttachment(url); imported.append(file); application.attachments.append(file) }
            catch { importError = error.localizedDescription }
        }
    }
}

private struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var event: StatusEvent
    let onApply: (StatusEvent) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit journey step").font(.title2.bold())
            Form {
                Picker("Status", selection: $event.status) {
                    ForEach(ApplicationStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Date recorded", isOn: Binding(get: { event.date != nil }, set: { event.date = $0 ? Date() : nil }))
                if event.date != nil {
                    DatePicker("Date", selection: Binding(get: { event.date ?? Date() }, set: { event.date = $0 }), displayedComponents: .date)
                }
            }
            Text("This updates the existing step. Save the application afterwards to keep the change.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply changes") { onApply(event); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420)
    }
}
