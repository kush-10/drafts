import SwiftUI

struct FullListView: View {
    enum Scope: String, CaseIterable { case all = "All", trash = "Trash" }
    @ObservedObject var store: NoteStore
    @ObservedObject var workspace: WorkspaceState
    let onOpen: (UUID) -> Void
    let onNew: () -> Void
    let onSettings: () -> Void
    let onTrash: (UUID) -> Void
    @StateObject private var editor = EditorBridge()
    @State private var scope: Scope = .all
    @State private var query = ""
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\Note.createdAt, order: .reverse)]
    @State private var confirmDeletion = false

    private var rows: [Note] {
        let source = scope == .trash ? store.trashedNotes : store.activeNotes
        return source.filter {
            $0.matches(query)
        }.sorted(using: sortOrder)
    }

    private var selectedNote: Note? { store.note(selection) }
    private var selectionBinding: Binding<UUID?> {
        Binding(get: { selection }, set: { id in
            guard store.flush() else { return }
            selection = id
            if let note = store.note(id), note.deletedAt == nil { workspace.currentID = id; editor.load(note) }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text("All notes").font(.system(size: 16, weight: .medium))
                Spacer(minLength: 0)
                TextField("Search notes", text: $query).textFieldStyle(.roundedBorder).frame(width: 240)
                Picker("Notes", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }.padding(20)

            VSplitView {
                Table(rows, selection: selectionBinding, sortOrder: $sortOrder) {
                    TableColumn("Note", value: \.title) { note in Text(note.title).lineLimit(1) }.width(min: 200, ideal: 300)
                    TableColumn("Created", value: \.createdAt) { note in
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }.width(min: 140, ideal: 155)
                    TableColumn("Edited", value: \.updatedAt) { note in
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }.width(min: 140, ideal: 155)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first {
                        if scope == .trash { Button("Restore") { store.restore(id) } }
                        else {
                            Button("Open in notepad") { onOpen(id) }
                            Button("Move to Trash") { onTrash(id); selection = nil }
                        }
                    }
                } primaryAction: { ids in if let id = ids.first, scope != .trash { onOpen(id) } }
                .onDeleteCommand { deleteSelected() }
                .frame(minHeight: 180)

                if let note = selectedNote {
                    VStack(spacing: 0) {
                        HStack {
                            Text(note.deletedAt == nil ? "Edit note" : "In Trash")
                                .foregroundStyle(DraftsTheme.secondary)
                            Spacer()
                            if note.deletedAt == nil { Button("Open in notepad") { onOpen(note.id) } }
                            else { Button("Restore") { store.restore(note.id); selection = nil } }
                        }.font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 10)
                        if note.deletedAt == nil {
                            RichEditor(note: note, bridge: editor) { id, content in store.update(id, content: content) }
                        } else { RichPreview(note: note) }
                    }.frame(minHeight: 160, idealHeight: 210, maxHeight: 280)
                }
            }
            HStack(spacing: 20) {
                Text("\(rows.count) notes").foregroundStyle(DraftsTheme.secondary)
                Spacer()
                if selection != nil {
                    Button(scope == .trash ? "Delete permanently…" : "Move to Trash", action: deleteSelected)
                }
                Button("New note  ⌘N", action: onNew)
                Button("Settings", action: onSettings)
            }.buttonStyle(.plain).font(.system(size: 11)).padding(16)
            SaveErrorBanner(store: store)
        }
        .font(.system(size: 12)).foregroundStyle(DraftsTheme.text)
        .background(DraftsTheme.surface).tint(DraftsTheme.accent).environment(\.colorScheme, .dark)
        .onChange(of: scope) { _, _ in if store.flush() { selection = nil } }
        .alert("Permanently delete this note?", isPresented: $confirmDeletion) {
            Button("Delete permanently", role: .destructive) { if let id = selection { store.deletePermanently(id); selection = nil } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        if scope == .trash { confirmDeletion = true }
        else { onTrash(id); selection = nil }
    }
}
