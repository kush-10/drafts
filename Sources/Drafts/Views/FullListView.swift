import SwiftUI

struct FullListView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var workspace: WorkspaceState
    let onOpen: (UUID) -> Void
    let onNew: () -> Void
    let onBack: () -> Void
    @ObservedObject var categories: CategoryStore
    var intelligence: IntelligenceController? = nil
    var showsNavigation = true
    @State private var sortOrder = [KeyPathComparator(\Note.updatedAt, order: .reverse)]
    @State private var confirmDeletion = false

    private var rows: [Note] {
        NotesFilter.rows(store: store, categories: categories, query: workspace.tableQuery,
                         trash: workspace.tableTrash, topic: workspace.tableTopic).sorted(using: sortOrder)
    }
    private var selectedIDs: Set<UUID> { workspace.tableSelection.intersection(Set(rows.map(\.id))) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if showsNavigation { Button(action: onBack) { Label("Editor", systemImage: "chevron.left") }.buttonStyle(.plain) }
                Spacer(minLength: 8)
                TextField("Search notes and topics", text: $workspace.tableQuery).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button("New note", action: onNew).buttonStyle(.plain)
            }.padding(16)
            HStack {
                Picker("Notes", selection: $workspace.tableTrash) { Text("All notes").tag(false); Text("Trash").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                Picker("Topic", selection: $workspace.tableTopic) {
                    Text("All topics").tag(nil as UUID?)
                    ForEach(categories.categories) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 230)
                Spacer()
                Text("⌘/⇧ click to select multiple").font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 12)
            if let intelligence, !workspace.tableTrash {
                OrganisationControls(intelligence: intelligence).padding(.horizontal, 16).padding(.bottom, 12)
            }
            Table(rows, selection: $workspace.tableSelection, sortOrder: $sortOrder) {
                TableColumn("Note", value: \.title) { note in Text(note.title).lineLimit(1) }.width(min: 150, ideal: 300)
                TableColumn("Topics") { note in Text(categories.names(for: note.id)).lineLimit(1) }.width(min: 80, ideal: 160)
                TableColumn("Edited", value: \.updatedAt) { note in Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)) }.width(min: 110, ideal: 150)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    if !workspace.tableTrash, ids.count == 1, let id = ids.first { Button("Open note") { onOpen(id) } }
                    Button(workspace.tableTrash ? "Restore selected" : "Move selected to Trash") { mutate(ids, restore: workspace.tableTrash) }
                }
            } primaryAction: { ids in if !workspace.tableTrash, ids.count == 1, let id = ids.first { onOpen(id) } }
            .onDeleteCommand { deleteSelected() }
            HStack(spacing: 18) {
                Text(selectedIDs.isEmpty ? "\(rows.count) notes" : "\(selectedIDs.count) selected")
                    .foregroundStyle(DraftsTheme.secondary)
                Spacer()
                if !selectedIDs.isEmpty {
                    if workspace.tableTrash {
                        Button("Restore") { mutate(selectedIDs, restore: true) }
                        Button("Delete permanently…") { confirmDeletion = true }
                    } else {
                        Menu("Topics") {
                            ForEach(categories.categories) { category in
                                Button("Add \(category.name)") { selectedIDs.forEach { categories.setManual(category.id, noteID: $0, included: true) } }
                                Button("Remove \(category.name)") { selectedIDs.forEach { categories.setManual(category.id, noteID: $0, included: false) } }
                            }
                            Divider()
                            Button("Use automatic topics") { selectedIDs.forEach { categories.useAutomatic(noteID: $0) } }
                        }
                        Button("Move to Trash") { mutate(selectedIDs, restore: false) }
                        if selectedIDs.count == 1, let id = selectedIDs.first { Button("Open") { onOpen(id) } }
                    }
                }
            }.buttonStyle(.plain).font(.system(size: 11)).padding(16)
        }
        .foregroundStyle(DraftsTheme.text).background(DraftsTheme.surface).tint(DraftsTheme.accent)
        .onChange(of: workspace.tableTrash) { _, _ in workspace.tableSelection = [] }
        .onChange(of: rows.map(\.id)) { _, ids in workspace.tableSelection.formIntersection(Set(ids)) }
        .alert("Permanently delete \(selectedIDs.count) selected notes?", isPresented: $confirmDeletion) {
            Button("Delete permanently", role: .destructive) {
                guard store.flush() else { return }
                selectedIDs.forEach { store.deletePermanently($0) }; workspace.tableSelection = []
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    private func mutate(_ ids: Set<UUID>, restore: Bool) {
        guard store.flush() else { return }
        for id in ids { if restore { store.restore(id) } else { store.trash(id) } }
        workspace.tableSelection = []
    }
    private func deleteSelected() {
        if workspace.tableTrash { confirmDeletion = true } else { mutate(selectedIDs, restore: false) }
    }
}

enum NotesFilter {
    static func rows(store: NoteStore, categories: CategoryStore, query: String, trash: Bool = false, topic: UUID? = nil) -> [Note] {
        let source = trash ? store.trashedNotes : store.activeNotes
        let parsed = SmartQuery(query, categories: categories.categories)
        guard let filters = parsed.categoryIDs(in: categories.categories) else { return [] }
        return source.filter { note in
            let labels = categories.labels(for: note.id).effective
            guard filters.isSubset(of: labels), topic.map({ labels.contains($0) }) ?? true else { return false }
            let names = categories.names(for: note.id)
            return parsed.text.split(whereSeparator: \.isWhitespace).allSatisfy { word in
                note.text.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
                names.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
