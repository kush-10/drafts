import SwiftUI

struct NotePickerView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var workspace: WorkspaceState
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void
    @State private var selectedID: UUID?

    private var results: [Note] { store.notesByCreation.filter { $0.matches(workspace.pickerQuery) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                PickerSearchField(query: $workspace.pickerQuery, onMove: move, onSubmit: openSelected, onDismiss: onDismiss)
                    .frame(height: 25)
                Button(action: onDismiss) { KeyCap(text: "esc") }.buttonStyle(.plain).focusable(false)
            }.padding(.horizontal, 20).padding(.vertical, 15)
            Divider().opacity(0.5)
            if results.isEmpty {
                Text("No matching notes").font(.system(size: 13)).foregroundStyle(DraftsTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(results) { note in
                                Button { onSelect(note.id) } label: {
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            if !note.preview.isEmpty {
                                                Text(note.preview).font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(selectedID == note.id ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).focusable(false).id(note.id)
                            }
                        }.padding(8)
                    }
                    .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
            HStack {
                Text("↑ ↓ Select    ↵ Open")
                Spacer()
                Text("\(results.count) notes")
            }.font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 540, height: 340)
        .foregroundStyle(DraftsTheme.text)
        .background(DraftsTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .onAppear { selectedID = results.first(where: { $0.id == workspace.currentID })?.id ?? results.first?.id }
        .onChange(of: workspace.pickerQuery) { _, _ in selectedID = results.first?.id }
        .onExitCommand(perform: onDismiss)
    }

    private func move(_ direction: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = results[min(max(0, current + direction), results.count - 1)].id
    }

    private func openSelected() {
        guard let note = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        onSelect(note.id)
    }
}

// A native field delegate handles arrows/Return/Escape before the field editor consumes them.
private struct PickerSearchField: NSViewRepresentable {
    @Binding var query: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NoteSearchField {
        let field = NoteSearchField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        field.textColor = EditorStyle.textColor
        field.placeholderString = "Search notes"
        field.setAccessibilityLabel("Search saved notes")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NoteSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PickerSearchField
        init(parent: PickerSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.query = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch NSStringFromSelector(commandSelector) {
            case "moveDown:": parent.onMove(1)
            case "moveUp:": parent.onMove(-1)
            case "insertNewline:": parent.onSubmit()
            case "cancelOperation:": parent.onDismiss()
            case "insertTab:", "insertBacktab:": break // Keep focus in the modal picker.
            default: return false
            }
            return true
        }
    }
}

final class NoteSearchField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isVisible else { return }
            window.makeFirstResponder(self)
        }
    }
}
