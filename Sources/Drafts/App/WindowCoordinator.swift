import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

private final class UtilityWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let notepadSize = NSSize(width: 760, height: 500)
    static let fullListSize = NSSize(width: 1000, height: 640)
    let store: NoteStore
    let preferences: PreferencesStore
    let hotKeys: HotKeyManager
    let workspace: WorkspaceState
    let editor = EditorBridge()
    private(set) var scratchpad: OverlayPanel?
    private(set) var fullListWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var previousApplication: NSRunningApplication?

    init(store: NoteStore, preferences: PreferencesStore, hotKeys: HotKeyManager, workspace: WorkspaceState = WorkspaceState()) {
        self.store = store
        self.preferences = preferences
        self.hotKeys = hotKeys
        self.workspace = workspace
        super.init()
        editor.onFind = { [weak self] in self?.showNotePicker() }
        editor.onCopyAndClose = { [weak self] in _ = self?.copyAndClose() }
        editor.onSettings = { [weak self] in self?.showSettings() }
        if store.note(workspace.currentID)?.deletedAt != nil || store.note(workspace.currentID) == nil {
            workspace.currentID = store.newestNote?.id
        }
    }

    func newBlank() {
        guard let note = store.newDraft(preferredID: workspace.currentID) else { showStorageError(); return }
        workspace.closePicker()
        workspace.currentID = note.id
        showScratchpad()
    }

    func openNewestNote() {
        // Open is deliberately not a toggle. Creation time, not edits or last selection, determines newest.
        guard store.flush() else { showStorageError(); return }
        if let note = store.newestNote { open(note.id) }
        else { newBlank() }
    }

    func selectNote(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        guard let note = store.note(id), note.deletedAt == nil else { return }
        workspace.currentID = id
        workspace.closePicker()
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        editor.load(note)
        editor.focus()
    }

    func open(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        guard store.note(id)?.deletedAt == nil, store.note(id) != nil else { return }
        workspace.closePicker()
        workspace.currentID = id
        showScratchpad()
    }

    func hideScratchpad() {
        guard store.flush() else { showStorageError(); return }
        workspace.closePicker()
        scratchpad?.orderOut(nil)
        runCleanup()
        returnFocus()
    }

    @discardableResult
    func copyAndClose(to pasteboard: NSPasteboard = .general) -> Bool {
        guard scratchpad?.isVisible == true, let note = store.note(workspace.currentID), note.deletedAt == nil else { return false }
        guard store.flush() else { showStorageError(); return false }
        pasteboard.clearContents()
        guard pasteboard.setString(note.text, forType: .string) else {
            let alert = NSAlert()
            alert.messageText = "Couldn’t copy the note"
            alert.informativeText = "Your note is still open and saved. Please try again."
            if let window = scratchpad { alert.beginSheetModal(for: window) }
            return false
        }
        hideScratchpad()
        return scratchpad?.isVisible != true
    }

    func showNotePicker() {
        guard scratchpad?.isVisible == true else { return }
        guard store.flush() else { showStorageError(); return }
        if !workspace.pickerVisible { workspace.pickerQuery = "" }
        workspace.pickerVisible = true
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
    }

    func dismissNotePicker() {
        workspace.closePicker()
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        editor.focus()
    }

    func cancelNotepad() {
        if workspace.pickerVisible { dismissNotePicker() }
        else { hideScratchpad() }
    }

    func trash(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        store.trash(id)
        if workspace.currentID == id {
            workspace.currentID = store.newestNote?.id
            if let note = store.newestNote { editor.load(note) }
            else { scratchpad?.orderOut(nil) }
        }
    }

    private func showScratchpad() {
        rememberExternalApplication()
        let comingFromTable = fullListWindow?.isVisible == true
        let wasHidden = scratchpad?.isVisible != true
        fullListWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        if scratchpad == nil {
            let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: Self.notepadSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Drafts — Notepad"
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onDismiss = { [weak self] in self?.cancelNotepad() }
            panel.delegate = self
            panel.contentView = hostingView(ScratchpadView(
                store: store, workspace: workspace, preferences: preferences, editor: editor,
                onSelect: { [weak self] id in self?.selectNote(id) },
                onFind: { [weak self] in self?.showNotePicker() },
                onDismissPicker: { [weak self] in self?.dismissNotePicker() },
                onHide: { [weak self] in self?.hideScratchpad() },
                onNew: { [weak self] in self?.newBlank() },
                onCopyAndClose: { [weak self] in _ = self?.copyAndClose() },
                onList: { [weak self] in self?.showFullList() }
            ), rounded: true)
            scratchpad = panel
        }
        scratchpad?.level = preferences.value.keepOnTop ? .floating : .normal
        position(scratchpad, size: Self.notepadSize)
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        if let note = store.note(workspace.currentID) { editor.load(note, force: comingFromTable || wasHidden) }
        scratchpad?.makeKeyAndOrderFront(nil)
        editor.focus()
        scratchpad?.invalidateShadow()
        let id = workspace.currentID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workspace.currentID == id, self.scratchpad?.isKeyWindow == true, !self.workspace.pickerVisible else { return }
            self.editor.focus()
        }
    }

    func showFullList() {
        guard store.flush() else { showStorageError(); return }
        rememberExternalApplication()
        workspace.closePicker()
        scratchpad?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        if fullListWindow == nil { fullListWindow = regularWindow(title: "Drafts — Full list", size: Self.fullListSize) }
        // Start with the whole table on each opening, not a stale editor or filter.
        fullListWindow?.contentView = hostingView(FullListView(
            store: store, workspace: workspace,
            onOpen: { [weak self] id in self?.open(id) },
            onNew: { [weak self] in self?.newBlank() },
            onSettings: { [weak self] in self?.showSettings() },
            onTrash: { [weak self] id in self?.trash(id) }
        ))
        position(fullListWindow, size: Self.fullListSize)
        NSApp.activate(ignoringOtherApps: true)
        fullListWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        guard store.flush() else { showStorageError(); return }
        workspace.closePicker()
        scratchpad?.orderOut(nil)
        fullListWindow?.orderOut(nil)
        if settingsWindow == nil {
            let window = regularWindow(title: "Drafts — Settings", size: NSSize(width: 520, height: 600))
            window.contentView = hostingView(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store))
            settingsWindow = window
        }
        position(settingsWindow, size: NSSize(width: 520, height: 600))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func runCleanup() {
        // Do not apply a partially edited retention interval while Settings is open.
        guard settingsWindow?.isVisible != true else { return }
        let tableEditor = fullListWindow?.isVisible == true ? (fullListWindow?.firstResponder as? DraftsTextView)?.editorBridge?.noteID : nil
        let editingID = scratchpad?.isVisible == true ? workspace.currentID : tableEditor
        store.cleanup(preferences: preferences.value, excluding: editingID)
        if store.note(workspace.currentID) == nil { workspace.currentID = store.newestNote?.id }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === scratchpad { hideScratchpad(); return false }
        guard store.flush() else { showStorageError(); return false }
        return true
    }

    private func regularWindow(title: String, size: NSSize) -> NSWindow {
        let window = UtilityWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.09, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func hostingView<V: View>(_ view: V, rounded: Bool = false) -> NSView {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark).tint(DraftsTheme.accent))
        if rounded {
            host.wantsLayer = true
            host.layer?.cornerRadius = DraftsTheme.cornerRadius
            host.layer?.cornerCurve = .continuous
            host.layer?.masksToBounds = true
        }
        return host
    }

    static func defaultFrame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func position(_ window: NSWindow?, size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let window, let frame = screen?.visibleFrame else { return }
        // No frame autosave: dragging is temporary, and every open uses the same anchor and size.
        let contentFrame = Self.defaultFrame(size: size, visibleFrame: frame)
        window.setFrame(window.frameRect(forContentRect: contentFrame), display: true)
    }

    private func rememberExternalApplication() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = app }
    }

    private func returnFocus() {
        if NSApp.isActive, fullListWindow?.isVisible != true, settingsWindow?.isVisible != true { previousApplication?.activate(options: []) }
    }

    private func showStorageError() {
        let alert = NSAlert()
        alert.messageText = "Your note needs attention"
        alert.informativeText = store.lastError ?? "Drafts couldn’t save this note. Keep it open and try again."
        alert.addButton(withTitle: "Keep Open")
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}
