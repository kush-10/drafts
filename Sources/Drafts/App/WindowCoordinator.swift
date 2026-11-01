import AppKit
import SwiftUI
import Combine

final class OverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var onNoteList: (() -> Void)?
    var onToggleExpansion: (() -> Void)?
    var onSmartSearch: (() -> Void)?
    var onSettings: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": if let action = onToggleExpansion { if !event.isARepeat { action() }; return true }
            case "k": if let action = onSmartSearch { action(); return true }
            case ",": if let action = onSettings { action(); return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class UtilityWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let notepadSize = NSSize(width: 760, height: 500)
    let store: NoteStore
    let preferences: PreferencesStore
    let hotKeys: HotKeyManager
    let workspace: WorkspaceState
    let editor = EditorBridge()
    let intelligence: IntelligenceController
    private(set) var scratchpad: OverlayPanel?
    private var settingsWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var frameBeforeExpansion: NSRect?
    private var themeSubscription: AnyCancellable?

    init(store: NoteStore, preferences: PreferencesStore, hotKeys: HotKeyManager, workspace: WorkspaceState = WorkspaceState()) {
        self.store = store
        self.preferences = preferences
        self.hotKeys = hotKeys
        self.workspace = workspace
        self.intelligence = IntelligenceController(store: store, preferences: preferences)
        super.init()
        themeSubscription = ThemeController.shared.$palette.sink { [weak self] palette in
            for window in [self?.scratchpad, self?.settingsWindow].compactMap({ $0 }) {
                window.appearance = palette.appearance
                if window !== self?.scratchpad { window.backgroundColor = ThemePalette.native(palette.background) }
            }
        }
        editor.onNoteList = { [weak self] in self?.showFullList() }
        editor.onSmartSearch = { [weak self] in self?.showSmartSearch() }
        editor.onToggleExpansion = { [weak self] in self?.toggleExpansion() }
        editor.onCopyAndClose = { [weak self] in _ = self?.copyAndClose() }
        editor.onSettings = { [weak self] in self?.showSettings() }
        editor.availableTopics = { [weak self] in self?.intelligence.categories.organisationTopics ?? [] }
        editor.onAssignTopic = { [weak self] noteID, topicID in
            self?.intelligence.categories.setManual(topicID, noteID: noteID, included: true) ?? false
        }
        editor.onTopicAccepted = { [weak self] id in self?.intelligence.rememberManualTopics(id) }
        editor.manualTopicLabels = { [weak self] id in self?.intelligence.categories.labels(for: id) ?? CategoryLabels() }
        editor.onRestoreManualLabels = { [weak self] id, labels in self?.intelligence.categories.restoreManualLabels(labels, noteID: id) ?? false }
        if store.note(workspace.currentID)?.deletedAt != nil || store.note(workspace.currentID) == nil {
            workspace.currentID = store.latestEditedNote?.id
        }
    }

    func newBlank() {
        guard let note = store.newDraft(preferredID: workspace.currentID) else { showStorageError(); return }
        workspace.closePicker()
        workspace.tableVisible = false
        workspace.currentID = note.id
        showScratchpad()
    }

    func toggleScratchpad() {
        if scratchpad?.isVisible == true { hideScratchpad() }
        else { openNewestNote() }
    }

    func openNewestNote() {
        // Reopening follows actual content edits, not creation, selection or category metadata.
        guard store.flush() else { showStorageError(); return }
        if let note = store.latestEditedNote { open(note.id) }
        else { newBlank() }
    }

    func selectNote(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        guard let note = store.note(id), note.deletedAt == nil else { return }
        workspace.currentID = id
        workspace.tableVisible = false
        workspace.closePicker()
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        editor.load(note)
        editor.focus()
    }

    func open(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        guard store.note(id)?.deletedAt == nil, store.note(id) != nil else { return }
        workspace.closePicker()
        workspace.tableVisible = false
        workspace.currentID = id
        showScratchpad()
    }

    func hideScratchpad(restoreFocus: Bool = true) {
        guard scratchpad?.attachedSheet == nil else { return }
        guard store.flush() else { showStorageError(); return }
        rememberWindow()
        workspace.closePicker()
        scratchpad?.orderOut(nil)
        runCleanup()
        if restoreFocus { returnFocus() }
    }

    func toggleExpansion() {
        guard let panel = scratchpad, panel.isVisible else { return }
        if let frame = frameBeforeExpansion {
            panel.setFrame(frame, display: true)
            frameBeforeExpansion = nil
            workspace.notepadExpanded = false
        } else if let screen = panel.screen ?? NSScreen.main {
            frameBeforeExpansion = panel.frame
            workspace.notepadExpanded = true
            panel.setFrame(screen.visibleFrame, display: true)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
    }

    // Focus changes are deliberately passive. Only explicit commands hide the notepad.
    func dismissForExternalInteraction() {}
    func handleMouseDown(in window: NSWindow?) {}
    func handleApplicationActivation(processIdentifier: pid_t) {}
    func windowDidResignKey(_ notification: Notification) {}

    func rememberWindow() {
        guard let panel = scratchpad, panel.isVisible else { return }
        workspace.rememberWindow(frame: panel.frame, expanded: workspace.notepadExpanded, restoreFrame: frameBeforeExpansion)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === scratchpad,
              workspace.notepadExpanded, let visible = panel.screen?.visibleFrame,
              panel.frame.size != visible.size else { return }
        // A manual resize exits expanded mode and becomes the size to remember.
        workspace.notepadExpanded = false
        frameBeforeExpansion = nil
    }

    @discardableResult
    func copyAndClose(to pasteboard: NSPasteboard = .general) -> Bool {
        guard scratchpad?.isVisible == true, !workspace.tableVisible, let note = store.note(workspace.currentID), note.deletedAt == nil else { return false }
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
        showSmartSearch()
    }

    func dismissNotePicker() {
        workspace.closePicker()
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        if !workspace.tableVisible { editor.focus() }
    }

    func showSmartSearch() {
        guard scratchpad?.isVisible == true else { return }
        guard store.flush() else { showStorageError(); return }
        if !workspace.pickerVisible { workspace.pickerQuery = "" }
        workspace.smartPicker = true
        workspace.pickerVisible = true
        workspace.searchFocusRequest += 1
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
    }

    func showGlobalSearch() {
        guard scratchpad?.attachedSheet == nil, settingsWindow?.attachedSheet == nil else { return }
        guard store.flush() else { showStorageError(); return }
        rememberExternalApplication()
        if scratchpad?.isVisible != true {
            if store.note(workspace.currentID) == nil || store.note(workspace.currentID)?.deletedAt != nil {
                workspace.currentID = store.latestEditedNote?.id
            }
            // Search is navigation, not New Note: an empty collection stays empty.
            showScratchpad()
        } else { scratchpad?.makeKeyAndOrderFront(nil) }
        showSmartSearch()
    }

    func cancelNotepad() {
        if workspace.pickerVisible { dismissNotePicker() }
        else { hideScratchpad() }
    }

    func trash(_ id: UUID) {
        guard store.flush() else { showStorageError(); return }
        store.trash(id)
        if workspace.currentID == id {
            workspace.currentID = store.latestEditedNote?.id
            if let note = store.latestEditedNote { editor.load(note) }
            else { rememberWindow(); scratchpad?.orderOut(nil) }
        }
    }

    private func showScratchpad() {
        rememberExternalApplication()
        let comingFromTable = workspace.tableVisible
        if comingFromTable { workspace.tableEditingID = nil }
        let wasHidden = scratchpad?.isVisible != true
        settingsWindow?.orderOut(nil)
        if scratchpad == nil {
            let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: Self.notepadSize), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            panel.contentMinSize = NSSize(width: 640, height: 380)
            panel.title = "Drafts — Notepad"
            panel.appearance = DraftsTheme.palette.appearance
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onDismiss = { [weak self] in self?.cancelNotepad() }
            panel.onNoteList = { [weak self] in self?.showFullList() }
            panel.onToggleExpansion = { [weak self] in self?.toggleExpansion() }
            panel.onSmartSearch = { [weak self] in self?.showSmartSearch() }
            panel.onSettings = { [weak self] in self?.showSettings() }
            panel.delegate = self
            panel.contentView = hostingView(ScratchpadView(
                store: store, workspace: workspace, preferences: preferences, editor: editor,
                onSelect: { [weak self] id in self?.selectNote(id) },
                onNoteList: { [weak self] in self?.showFullList() },
                onDismissPicker: { [weak self] in self?.dismissNotePicker() },
                onHide: { [weak self] in self?.hideScratchpad() },
                onNew: { [weak self] in self?.newBlank() },
                onCopyAndClose: { [weak self] in _ = self?.copyAndClose() },
                onToggleExpansion: { [weak self] in self?.toggleExpansion() }, intelligence: intelligence
            ), rounded: true)
            scratchpad = panel
        }
        scratchpad?.level = preferences.value.keepOnTop ? .floating : .normal
        if wasHidden { restoreWindowSize() }
        scratchpad?.contentView?.layoutSubtreeIfNeeded()
        if !workspace.tableVisible, let note = store.note(workspace.currentID) { editor.load(note, force: comingFromTable || wasHidden) }
        scratchpad?.makeKeyAndOrderFront(nil)
        if !workspace.tableVisible { editor.focus() }
        scratchpad?.invalidateShadow()
        let id = workspace.currentID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workspace.currentID == id, self.scratchpad?.isKeyWindow == true, !self.workspace.pickerVisible, !self.workspace.tableVisible else { return }
            self.editor.focus()
        }
    }

    func showFullList() {
        guard store.flush() else { showStorageError(); return }
        rememberExternalApplication()
        workspace.tableEditingID = nil
        workspace.closePicker()
        workspace.tableVisible = true
        showScratchpad()
    }

    func showSettings() {
        guard store.flush() else { showStorageError(); return }
        if scratchpad?.isVisible == true { hideScratchpad(restoreFocus: false) }
        workspace.closePicker()
        scratchpad?.orderOut(nil)
        if settingsWindow == nil {
            let window = regularWindow(title: "Drafts — Settings", size: NSSize(width: 820, height: 640))
            window.contentView = hostingView(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store, intelligence: intelligence,
                                                         initialPage: hotKeys.error == nil ? .general : .shortcuts))
            settingsWindow = window
        }
        position(settingsWindow, size: NSSize(width: 820, height: 640))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func runCleanup() {
        // Do not apply a partially edited retention interval while Settings is open.
        guard settingsWindow?.isVisible != true else { return }
        let editingID = scratchpad?.isVisible == true && !workspace.tableVisible ? workspace.currentID : nil
        store.cleanup(preferences: preferences.value, excluding: editingID)
        if store.note(workspace.currentID) == nil { workspace.currentID = store.latestEditedNote?.id }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === scratchpad { hideScratchpad(); return false }
        guard store.flush() else { showStorageError(); return false }
        return true
    }

    private func regularWindow(title: String, size: NSSize) -> NSWindow {
        let window = UtilityWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.appearance = DraftsTheme.palette.appearance
        window.backgroundColor = ThemePalette.native(DraftsTheme.palette.background)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func hostingView<V: View>(_ view: V, rounded: Bool = false) -> NSView {
        let host = NSHostingView(rootView: ThemedRoot(content: view))
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

    private func restoreWindowSize() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let panel = scratchpad, let visible = screen?.visibleFrame else { return }
        let saved = workspace.rememberedWindow(minutes: preferences.value.sizeMemoryMinutes)
        func frame(_ width: Double, _ height: Double) -> NSRect {
            Self.defaultFrame(size: NSSize(width: min(max(640, width), visible.width), height: min(max(380, height), visible.height)), visibleFrame: visible)
        }
        workspace.notepadExpanded = saved?.expanded ?? false
        if let saved, saved.expanded {
            frameBeforeExpansion = frame(saved.restoreWidth, saved.restoreHeight)
            panel.setFrame(visible, display: true)
        } else {
            frameBeforeExpansion = nil
            panel.setFrame(frame(saved?.width ?? Self.notepadSize.width, saved?.height ?? Self.notepadSize.height), display: true)
        }
    }

    private func rememberExternalApplication() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = app }
    }

    private func returnFocus() {
        if NSApp.isActive, settingsWindow?.isVisible != true { previousApplication?.activate(options: []) }
    }

    private func showStorageError() {
        let alert = NSAlert()
        alert.messageText = "Your note needs attention"
        alert.informativeText = store.lastError ?? "Drafts couldn’t save this note. Keep it open and try again."
        alert.addButton(withTitle: "Keep Open")
        if let window = scratchpad?.isVisible == true ? scratchpad : NSApp.keyWindow {
            guard window.attachedSheet == nil else { return }
            alert.beginSheetModal(for: window)
        }
        else { alert.runModal() }
    }
}
