import SwiftUI

struct SmartSearchView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var intelligence: IntelligenceController
    @ObservedObject var categories: CategoryStore
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void
    @State private var selectedID: UUID?
    @State private var selectedSuggestion = 0

    init(store: NoteStore, workspace: WorkspaceState, intelligence: IntelligenceController, onSelect: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void) {
        self.store = store; self.workspace = workspace; self.intelligence = intelligence
        categories = intelligence.categories; self.onSelect = onSelect; self.onDismiss = onDismiss
    }

    private var query: SmartQuery { SmartQuery(workspace.pickerQuery, categories: categories.categories) }
    private var results: [Note] {
        return NotesFilter.rows(store: store, categories: categories, query: workspace.pickerQuery).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var suggestions: [String] {
        guard let slash = workspace.pickerQuery.range(of: "/", options: .backwards) else { return [] }
        let suffix = String(workspace.pickerQuery[slash.upperBound...])
        if suffix.hasSuffix(" ") || suffix.hasSuffix("\"") { return [] }
        let prefix = suffix.replacingOccurrences(of: "\"", with: "")
        if categories.categories.contains(where: { $0.name.caseInsensitiveCompare(prefix) == .orderedSame }) { return [] }
        let names = categories.categories.map(\.name).filter { $0.localizedCaseInsensitiveContains(prefix) }
        return Array(names.prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").foregroundStyle(DraftsTheme.accent)
                PickerSearchField(query: $workspace.pickerQuery, onMove: move, onSubmit: submit, onDismiss: onDismiss,
                                   placeholder: "Search notes and topics", focusRequest: workspace.searchFocusRequest, onComplete: complete)
                    .frame(height: 25)
                Button(action: onDismiss) { KeyCap(text: "esc") }.buttonStyle(.plain).focusable(false)
            }.padding(.horizontal, 20).padding(.vertical, 15)
            Divider().opacity(0.5)
            if !suggestions.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, name in
                        Button { accept(name) } label: {
                            HStack { Text(name); Spacer() }
                                .padding(10).background(index == selectedSuggestion ? DraftsTheme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).focusable(false)
                    }
                }.padding(8)
                Spacer(minLength: 0)
            } else if results.isEmpty {
                Text(emptyMessage).font(.system(size: 12)).foregroundStyle(DraftsTheme.secondary)
                    .multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(results) { note in
                                Button { onSelect(note.id) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(note.preview).font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary).lineLimit(1)
                                        let names = categories.names(for: note.id)
                                        if !names.isEmpty { Text(names).font(.system(size: 10)).foregroundStyle(DraftsTheme.accent).lineLimit(1) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(selectedID == note.id ? DraftsTheme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).focusable(false).id(note.id)
                            }
                        }.padding(8)
                    }.onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
            HStack {
                Text("↑ ↓ Select    ↵ Open")
                Spacer()
                Text("\(results.count) notes")
            }.font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 540, height: 340).foregroundStyle(DraftsTheme.text)
        .background(DraftsTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DraftsTheme.accent.opacity(0.18)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { selectedID = results.first?.id }
        .onChange(of: workspace.pickerQuery) { _, _ in selectedID = results.first?.id; selectedSuggestion = 0 }
    }

    private var emptyMessage: String {
        if query.categoryIDs(in: categories.categories) == nil { return "Unknown topic. Type / to choose a topic." }
        return "No matching notes"
    }

    private func move(_ direction: Int) {
        if !suggestions.isEmpty { selectedSuggestion = min(max(0, selectedSuggestion + direction), suggestions.count - 1); return }
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(0, index + direction), results.count - 1)].id
    }

    private func accept(_ name: String) {
        workspace.pickerQuery = SmartQuery.completing(workspace.pickerQuery, with: name)
    }

    private func complete() {
        if !suggestions.isEmpty { accept(suggestions[min(selectedSuggestion, suggestions.count - 1)]) }
    }

    private func submit() {
        if !suggestions.isEmpty { accept(suggestions[min(selectedSuggestion, suggestions.count - 1)]); return }
        if let note = results.first(where: { $0.id == selectedID }) ?? results.first { onSelect(note.id) }
    }
}
