import SwiftUI

final class WorkspaceState: ObservableObject {
    private let defaults: UserDefaults
    @Published var currentID: UUID? {
        didSet { defaults.set(currentID?.uuidString, forKey: "activeNoteID") }
    }
    @Published var pickerVisible = false
    @Published var pickerQuery = ""
    @Published var notepadExpanded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentID = defaults.string(forKey: "activeNoteID").flatMap(UUID.init(uuidString:))
    }

    func closePicker() { pickerVisible = false; pickerQuery = "" }
}

struct ScratchpadView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var editor: EditorBridge
    let onSelect: (UUID) -> Void
    let onNoteList: () -> Void
    let onDismissPicker: () -> Void
    let onHide: () -> Void
    let onNew: () -> Void
    let onCopyAndClose: () -> Void
    let onToggleExpansion: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if let note = store.note(workspace.currentID) {
                    RichEditor(note: note, bridge: editor) { id, content in store.update(id, content: content) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(symbol: "", title: "No note selected", subtitle: "Press ⌘N to create one.")
                }
                footer
                SaveErrorBanner(store: store)
            }
            .allowsHitTesting(!workspace.pickerVisible)
            .accessibilityHidden(workspace.pickerVisible)

            if workspace.pickerVisible {
                Color.black.opacity(0.32).contentShape(Rectangle()).onTapGesture(perform: onDismissPicker)
                NotePickerView(store: store, workspace: workspace, onSelect: onSelect, onDismiss: onDismissPicker)
                    .padding(.top, 30)
            }
        }
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: DraftsTheme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .tint(DraftsTheme.accent)
    }

    private var footer: some View {
        HStack(spacing: 19) {
            Text("\(store.note(workspace.currentID)?.wordCount ?? 0) words")
                .monospacedDigit().fixedSize()
                .help(store.pendingCount > 0 ? "Saving…" : "Saved on this Mac. Drag here to move the window.")
            Spacer(minLength: 8)
            action("Notes", key: LocalCommand.noteList.label, perform: onNoteList)
            separator
            action("New", key: "⌘N", perform: onNew)
            separator
            action("Copy & close", key: LocalCommand.copyAndClose.label, perform: onCopyAndClose)
            separator
            action("Hide", key: "esc", perform: onHide)
            separator
            action(workspace.notepadExpanded ? "Restore" : "Expand", key: LocalCommand.toggleExpansion.label, perform: onToggleExpansion)
        }
        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
        .padding(.horizontal, 20).frame(height: 44)
        .background(WindowDragRegion())
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .top) { Color.white.opacity(0.045).frame(height: 1) }
        .help("Formatting: ⌘B bold · ⌘I italic · ⌘U underline · ⇧⌘B bullets")
    }

    private var separator: some View { Color.white.opacity(0.10).frame(width: 1, height: 12) }
    private func action(_ title: String, key: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { HStack(spacing: 7) { Text(title); KeyCap(text: key) } }
            .buttonStyle(.plain).focusable(false).fixedSize()
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
