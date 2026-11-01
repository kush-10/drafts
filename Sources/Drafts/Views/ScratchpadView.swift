import SwiftUI

final class WorkspaceState: ObservableObject {
    private let defaults: UserDefaults
    @Published var currentID: UUID? {
        didSet { defaults.set(currentID?.uuidString, forKey: "activeNoteID") }
    }
    @Published var pickerVisible = false
    @Published var pickerQuery = ""
    @Published var smartPicker = false
    @Published var searchFocusRequest = 0
    @Published var notepadExpanded = false
    @Published var tableEditingID: UUID?
    @Published var tableVisible = false
    @Published var tableQuery = ""
    @Published var tableSelection = Set<UUID>()
    @Published var tableTrash = false
    @Published var tableTopic: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentID = defaults.string(forKey: "activeNoteID").flatMap(UUID.init(uuidString:))
    }

    struct SavedWindow: Codable {
        var width: Double
        var height: Double
        var expanded: Bool
        var restoreWidth: Double
        var restoreHeight: Double
        var hiddenAt: Date
    }

    func rememberWindow(frame: NSRect, expanded: Bool, restoreFrame: NSRect?, now: Date = Date()) {
        let saved = SavedWindow(width: frame.width, height: frame.height, expanded: expanded,
                                restoreWidth: Double(restoreFrame?.width ?? frame.width),
                                restoreHeight: Double(restoreFrame?.height ?? frame.height), hiddenAt: now)
        defaults.set(try? JSONEncoder().encode(saved), forKey: "windowMemory.v1")
    }

    func rememberedWindow(minutes: Int, now: Date = Date()) -> SavedWindow? {
        guard let data = defaults.data(forKey: "windowMemory.v1"),
              let saved = try? JSONDecoder().decode(SavedWindow.self, from: data),
              saved.width.isFinite, saved.height.isFinite, saved.width > 0, saved.height > 0,
              saved.restoreWidth.isFinite, saved.restoreHeight.isFinite, saved.restoreWidth > 0, saved.restoreHeight > 0,
              now >= saved.hiddenAt, now.timeIntervalSince(saved.hiddenAt) < Double(max(1, minutes)) * 60 else { return nil }
        return saved
    }

    func closePicker() { pickerVisible = false; pickerQuery = ""; smartPicker = false }
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
    var intelligence: IntelligenceController? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                toolbar
                if workspace.tableVisible, let intelligence {
                    FullListView(store: store, workspace: workspace, onOpen: onSelect, onNew: onNew,
                                 onBack: onDismissTable, categories: intelligence.categories, intelligence: intelligence, showsNavigation: false)
                } else if let note = store.note(workspace.currentID) {
                    RichEditor(note: note, bridge: editor) { id, content in store.update(id, content: content) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomLeading) { topicSuggestions }
                } else {
                    EmptyState(symbol: "", title: "No note selected", subtitle: "Press ⌘N to create one.")
                }
                SaveErrorBanner(store: store)
            }
            .allowsHitTesting(!workspace.pickerVisible)
            .accessibilityHidden(workspace.pickerVisible)

            if workspace.pickerVisible {
                Color.black.opacity(0.32).contentShape(Rectangle()).onTapGesture(perform: onDismissPicker)
                if let intelligence, workspace.smartPicker {
                    SmartSearchView(store: store, workspace: workspace, intelligence: intelligence, onSelect: onSelect, onDismiss: onDismissPicker)
                        .padding(.top, 30)
                } else {
                    NotePickerView(store: store, workspace: workspace, onSelect: onSelect, onDismiss: onDismissPicker)
                        .padding(.top, 30)
                }
            }
        }
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: DraftsTheme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, DraftsTheme.palette.scheme)
        .tint(DraftsTheme.accent)
    }

    @ViewBuilder private var topicSuggestions: some View {
        if let completion = editor.topicCompletion {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assign topic").font(.system(size: 11, weight: .semibold)).foregroundStyle(DraftsTheme.secondary)
                ForEach(Array(completion.topics.enumerated()), id: \.element.id) { index, topic in
                    Button { editor.acceptTopicCompletion(at: index) } label: {
                        HStack { Image(systemName: "tag"); Text(topic.name); Spacer(); if index == editor.selectedTopicIndex { Text("↵") } }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(index == editor.selectedTopicIndex ? DraftsTheme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).focusable(false)
                }
                Text("↑↓ choose · Enter/Tab assign · Esc cancel")
                    .font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
            }
            .font(.system(size: 12)).foregroundStyle(DraftsTheme.text)
            .padding(12).frame(width: 280)
            .background(DraftsTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DraftsTheme.secondary.opacity(0.25)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3).padding(16)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            if workspace.tableVisible {
                Button(action: onDismissTable) { Label("Editor", systemImage: "chevron.left") }
                    .buttonStyle(.plain).focusable(false)
                Text(workspace.tableTrash ? "Trash" : "All notes").fixedSize()
            } else {
                Text("\(store.note(workspace.currentID)?.wordCount ?? 0) words")
                    .monospacedDigit().fixedSize()
                    .help(store.pendingCount > 0 ? "Saving…" : "Saved on this Mac")
                Button("All notes", action: onNoteList).buttonStyle(.plain).focusable(false)
            }
            WindowDragRegion()
                .frame(minWidth: 96, maxWidth: .infinity).frame(height: 44)
                .overlay { Image(systemName: "ellipsis").foregroundStyle(DraftsTheme.secondary.opacity(0.6)).allowsHitTesting(false) }
                .help("Drag to move the window")
            if !workspace.tableVisible, let intelligence, let id = workspace.currentID {
                CategoryAssignmentMenu(store: intelligence.categories, noteID: id)
                    .frame(maxWidth: 280, alignment: .trailing)
            }
        }
        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
        .padding(.horizontal, 20).frame(height: 44)
        .background(DraftsTheme.text.opacity(0.02))
        .overlay(alignment: .bottom) { DraftsTheme.text.opacity(0.065).frame(height: 1) }
    }

    private func onDismissTable() {
        guard store.flush() else { return }
        workspace.tableVisible = false
        DispatchQueue.main.async { editor.focus() }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(true)
            setAccessibilityRole(.handle)
            setAccessibilityLabel("Move Drafts window")
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
        }
    }
}
