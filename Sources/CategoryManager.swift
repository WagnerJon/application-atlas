import SwiftUI
import AppKit

struct CategoryManager: View {
    @EnvironmentObject private var store: ApplicationStore
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [ApplicationCategory] = []
    @State private var original: [ApplicationCategory] = []
    @State private var reassignments: [String: String] = [:]
    @State private var newName = ""
    @State private var removing: ApplicationCategory?
    @State private var error: String?
    @State private var editingIcon: ApplicationCategory?
    private var validationMessage: String? {
        do { try ApplicationCategory.validate(categories, applications: []); return nil }
        catch { return error.localizedDescription }
    }
    private var canAdd: Bool {
        let name = ApplicationCategory.normalizedName(newName)
        return !name.isEmpty && newName.trimmingCharacters(in: .whitespacesAndNewlines).count <= 40 && !categories.contains { ApplicationCategory.normalizedName($0.name) == name }
    }
    private func count(_ category: ApplicationCategory) -> Int {
        store.applications.filter { (reassignments[$0.kind.rawValue] ?? $0.kind.rawValue) == category.id }.count
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your categories").font(.title2.bold())
                    Text("Make room for every kind of opportunity.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil || !store.canWrite)
            }
            Text("Click an icon to change its symbol or emoji. Rename categories below or add your own. The sidebar, editor, and Sankey update together when you save.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($categories) { $category in
                        HStack(spacing: 12) {
                            Button { editingIcon = category } label: {
                                CategoryIconView(icon: category.effectiveIcon).font(.system(size: 20))
                                    .foregroundStyle(category.kind.color).frame(width: 32, height: 30)
                            }.buttonStyle(.bordered).help("Change icon for \(category.name)")
                                .accessibilityLabel("Change icon for \(category.name)")
                            TextField("Category name", text: $category.name).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Category name: \(category.name)")
                            Text("\(count(category)) applications").font(.caption).foregroundStyle(.secondary).frame(width: 95, alignment: .trailing)
                            Button {
                                if count(category) > 0 { removing = category }
                                else { remove(category, movingTo: nil) }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).disabled(categories.count <= 1)
                                .help(categories.count <= 1 ? "Keep at least one category" : "Remove \(category.name)")
                                .accessibilityLabel("Remove \(category.name)")
                        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(maxHeight: 300)
            HStack {
                TextField("New category, e.g. Fellowship", text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit { if canAdd { add() } }
                Button { add() } label: { Label("Add category", systemImage: "plus") }.disabled(!canAdd)
            }
            if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Removing a category never deletes applications. You’ll choose another category for them.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 660)
            .onAppear { categories = store.categories; original = store.categories }
            .sheet(item: $editingIcon) { category in
                CategoryIconPicker(category: category) { icon in
                    if let index = categories.firstIndex(where: { $0.id == category.id }) { categories[index].icon = icon }
                    editingIcon = nil
                }
            }
            .sheet(item: $removing) { category in
                CategoryDestination(category: category, count: count(category), options: categories.filter { $0.id != category.id }) { target in
                    remove(category, movingTo: target)
                    removing = nil
                }
            }
    }
    private func add() {
        guard canAdd else { return }
        categories.append(ApplicationCategory(id: UUID().uuidString, name: newName.trimmingCharacters(in: .whitespacesAndNewlines)))
        newName = ""
    }
    private func remove(_ category: ApplicationCategory, movingTo target: String?) {
        guard categories.count > 1 else { return }
        if let target {
            for (source, destination) in reassignments where destination == category.id { reassignments[source] = target }
            reassignments[category.id] = target
        }
        categories.removeAll { $0.id == category.id }
    }
    private func save() {
        guard store.categories == original else {
            error = "Categories changed in another window. Cancel and reopen this dialog to use the latest categories."
            return
        }
        if store.updateCategories(categories, reassignments: reassignments) { dismiss() }
        else { error = store.error; store.error = nil }
    }
}
private struct CategoryDestination: View {
    @Environment(\.dismiss) private var dismiss
    let category: ApplicationCategory
    let count: Int
    let options: [ApplicationCategory]
    let onMove: (String) -> Void
    @State private var target: String
    init(category: ApplicationCategory, count: Int, options: [ApplicationCategory], onMove: @escaping (String) -> Void) {
        self.category = category; self.count = count; self.options = options; self.onMove = onMove
        _target = State(initialValue: options.first?.id ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remove \(category.name)?").font(.title2.bold())
            Text("Move its \(count) applications to another category. Their documents and journey steps will be kept.")
            Picker("Move to", selection: $target) { ForEach(options) { Text($0.name).tag($0.id) } }
            Text("Changes take effect when you save your categories.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move applications") { onMove(target) }.buttonStyle(.borderedProminent)
                    .disabled(!options.contains { $0.id == target })
            }
        }.padding(24).frame(width: 430)
    }
}

private struct CategoryIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    let category: ApplicationCategory
    let onApply: (CategoryIcon?) -> Void
    @State private var selection: CategoryIcon
    @State private var emoji: String
    @State private var useEmoji: Bool
    @FocusState private var emojiFocused: Bool
    init(category: ApplicationCategory, onApply: @escaping (CategoryIcon?) -> Void) {
        self.category = category; self.onApply = onApply
        _selection = State(initialValue: category.effectiveIcon)
        if case .emoji(let text) = category.effectiveIcon {
            _emoji = State(initialValue: text); _useEmoji = State(initialValue: true)
        } else {
            _emoji = State(initialValue: ""); _useEmoji = State(initialValue: false)
        }
    }
    private var chosenIcon: CategoryIcon { useEmoji ? .emoji(emoji.trimmingCharacters(in: .whitespacesAndNewlines)) : selection }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                CategoryIconView(icon: chosenIcon.isValid ? chosenIcon : category.effectiveIcon)
                    .font(.system(size: 30)).foregroundStyle(category.kind.color).frame(width: 44, height: 44)
                Text("Icon for \(category.name)").font(.title2.bold()).lineLimit(2)
            }
            Picker("Icon style", selection: $useEmoji) {
                Text("Symbol").tag(false)
                Text("Emoji").tag(true)
            }.pickerStyle(.segmented)
                .onChange(of: useEmoji) { _, enabled in
                    emojiFocused = enabled
                    if !enabled, case .emoji = selection { selection = .symbol(category.kind.icon) }
                }
            if useEmoji {
                HStack {
                    TextField("Enter one emoji", text: $emoji).textFieldStyle(.roundedBorder).font(.title2).focused($emojiFocused)
                    Button("Emoji picker…") {
                        emojiFocused = true
                        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                    }
                }
                Text("Type or paste one emoji, including flags or combined emoji.")
                    .font(.caption).foregroundStyle(.secondary)
                if !emoji.isEmpty && !chosenIcon.isValid {
                    Text("Please enter a single emoji.").font(.caption).foregroundStyle(.orange)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(CategoryIcon.symbols, id: \.self) { name in
                        Button { selection = .symbol(name) } label: {
                            Image(systemName: name).font(.system(size: 22)).frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(category.kind.color)
                                .background(selection == .symbol(name) ? category.kind.color.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == .symbol(name) ? category.kind.color : .clear))
                        }.buttonStyle(.plain).help(CategoryIcon.symbolLabel(name)).accessibilityLabel(CategoryIcon.symbolLabel(name))
                    }
                }
            }
            Text("Save your categories after applying the icon.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Use default") { onApply(nil) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply icon") { onApply(chosenIcon) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(!chosenIcon.isValid)
            }
        }.padding(24).frame(width: 430)
    }
}
