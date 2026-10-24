import AppKit
import SwiftUI
import XCTest
@testable import Drafts

final class WorkflowTests: XCTestCase {
    private var directory: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: NoteStore!
    private var preferences: PreferencesStore!
    private var workspace: WorkspaceState!
    private var hotKeys: HotKeyManager!
    private var coordinator: WindowCoordinator!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Window tests need a macOS display session.") }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftsWorkflowTests-\(UUID())")
        suite = "DraftsWorkflowTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        store = NoteStore(directory: directory)
        preferences = PreferencesStore(defaults: defaults)
        workspace = WorkspaceState(defaults: defaults)
        hotKeys = HotKeyManager()
        coordinator = WindowCoordinator(store: store, preferences: preferences, hotKeys: hotKeys, workspace: workspace)
    }

    override func tearDownWithError() throws {
        coordinator?.scratchpad?.orderOut(nil)
        coordinator?.fullListWindow?.orderOut(nil)
        coordinator = nil
        store?.flush()
        hotKeys = nil
        if let suite { defaults?.removePersistentDomain(forName: suite) }
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testExplicitOpenBringsNoteForwardWithoutHidingIt() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.openNewestNote()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(workspace.currentID, id)
        coordinator.hideScratchpad()
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, id)
        XCTAssertEqual(store.activeNotes.count, 1)
    }

    func testShortcutRepeatedlyShowsAndHidesWithoutCreatingExtraBlankNotes() throws {
        coordinator.toggleScratchpad()
        let id = try XCTUnwrap(workspace.currentID)
        for _ in 0..<5 {
            XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
            coordinator.toggleScratchpad()
            XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
            coordinator.toggleScratchpad()
            XCTAssertEqual(workspace.currentID, id)
        }
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(NoteStore(directory: directory).notes.count, 1)
    }

    func testShortcutHidesAndFlushesPendingEditsBeforeReopeningNewestCreatedNote() throws {
        let older = try XCTUnwrap(store.create(content: EditorStyle.plain("Older"), now: Date().addingTimeInterval(-200)))
        let newest = try XCTUnwrap(store.create(content: EditorStyle.plain("Newest"), now: Date().addingTimeInterval(-100)))
        coordinator.open(older.id)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Edited older", replacementRange: NSRange(location: 0, length: view.string.utf16.count))
        XCTAssertEqual(store.pendingCount, 1)
        coordinator.toggleScratchpad()
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(NoteStore(directory: directory).note(older.id)?.text, "Edited older")
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(workspace.currentID, newest.id)
        XCTAssertEqual(view.string, "Newest")
        XCTAssertEqual(store.notes.count, 2)
    }

    func testShortcutHidesPickerAndNoteTogetherAndReopensEditor() throws {
        coordinator.toggleScratchpad()
        coordinator.showNotePicker()
        _ = try waitForPickerSearchField()
        workspace.pickerQuery = "search"
        coordinator.toggleScratchpad()
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertEqual(workspace.pickerQuery, "")
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === coordinator.editor.textView)
    }

    func testShortcutKeepsUnsavedNoteOpenOnFailureAndCanRetry() throws {
        coordinator.toggleScratchpad()
        let id = try XCTUnwrap(workspace.currentID)
        // Block atomic writes with a directory at this test note's file path.
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        coordinator.editor.textView?.insertText("Keep unsaved edits", replacementRange: NSRange(location: 0, length: 0))
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.note(id)?.text, "Keep unsaved edits")
        XCTAssertNotNil(store.lastError)
        if let sheet = coordinator.scratchpad?.attachedSheet { coordinator.scratchpad?.endSheet(sheet) }
        try FileManager.default.removeItem(at: file)
        coordinator.toggleScratchpad()
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Keep unsaved edits")
    }

    func testShortcutHidingAppliesOnlyOptInRetention() throws {
        let old = try XCTUnwrap(store.create(content: EditorStyle.plain("Expired note"), now: Date().addingTimeInterval(-120)))
        coordinator.toggleScratchpad()
        coordinator.toggleScratchpad()
        XCTAssertNotNil(store.note(old.id))
        preferences.value.autoDeleteEnabled = true
        preferences.value.retentionAmount = 1
        preferences.value.retentionUnit = .minutes
        coordinator.toggleScratchpad()
        coordinator.toggleScratchpad()
        XCTAssertNil(store.note(old.id))
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.activeNotes.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.newestNote).isBlank)
    }

    func testOpenChoosesNewestCreatedNotMostRecentlyEditedOrSelected() throws {
        let old = try XCTUnwrap(store.create(content: EditorStyle.plain("Older"), now: Date().addingTimeInterval(-200)))
        let newest = try XCTUnwrap(store.create(content: EditorStyle.plain("Newest"), now: Date().addingTimeInterval(-100)))
        store.update(old.id, content: EditorStyle.plain("Edited just now"))
        coordinator.open(old.id)
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, newest.id)
        XCTAssertEqual(coordinator.editor.textView?.string, "Newest")
        XCTAssertEqual(store.activeNotes.count, 2)
    }

    func testPickerSelectionDoesNotMoveWindowOrCreateNotes() throws {
        coordinator.newBlank()
        let older = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Older note", replacementRange: NSRange(location: 0, length: 0))
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + 40, y: panel.frame.minY + 40))
        let moved = panel.frame
        coordinator.showNotePicker()
        coordinator.selectNote(older)
        XCTAssertEqual(workspace.currentID, older)
        XCTAssertEqual(panel.frame, moved)
        XCTAssertEqual(store.activeNotes.count, 2)
        XCTAssertFalse(workspace.pickerVisible)
    }

    func testEscapeHidesWithoutLosingContents() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Keep this #work", replacementRange: view.selectedRange())
        view.cancelOperation(nil)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.note(id)?.text, "Keep this #work")
        coordinator.openNewestNote()
        XCTAssertEqual(view.string, "Keep this #work")
    }

    func testNewNoteIsBlankAndImmediatelyFocusedWithoutOverwritingPreviousNote() throws {
        coordinator.newBlank()
        let first = try XCTUnwrap(workspace.currentID)
        let view = try XCTUnwrap(coordinator.editor.textView)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === view)
        view.insertText("First thought", replacementRange: view.selectedRange())
        coordinator.newBlank()
        let second = try XCTUnwrap(workspace.currentID)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(view.string, "")
        XCTAssertEqual(coordinator.editor.noteID, second)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === view)
        view.insertText("Second thought #home", replacementRange: view.selectedRange())
        coordinator.hideScratchpad()
        coordinator.openNewestNote()
        XCTAssertEqual(view.string, "Second thought #home")
        XCTAssertEqual(store.note(first)?.text, "First thought")
        XCTAssertEqual(NoteStore(directory: directory).activeNotes.count, 2)
    }

    func testCompactWindowAndEveryOpenResetTemporaryPositionAndSize() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let original = panel.frame
        XCTAssertEqual(original.size, WindowCoordinator.notepadSize)
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        panel.setFrameOrigin(NSPoint(x: original.minX + 75, y: original.minY + 50))
        panel.setContentSize(NSSize(width: 850, height: 550))
        coordinator.hideScratchpad()
        coordinator.openNewestNote()
        XCTAssertEqual(panel.frame, original)
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
        XCTAssertEqual(panel.contentView?.layer?.cornerRadius, DraftsTheme.cornerRadius)
    }

    func testDefaultPositionIsCenteredAndDeterministic() {
        let screen = NSRect(x: 100, y: 50, width: 1600, height: 1000)
        let frame = WindowCoordinator.defaultFrame(size: WindowCoordinator.notepadSize, visibleFrame: screen)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.midY, screen.midY)
        XCTAssertEqual(frame.size, WindowCoordinator.notepadSize)
    }

    func testEditorTracksViewportAndLongLinesWrapInsteadOfClipping() throws {
        coordinator.newBlank()
        let host = try XCTUnwrap(coordinator.scratchpad?.contentView)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(find(EditorScrollView.self, in: host))
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText(String(repeating: "longword", count: 150), replacementRange: view.selectedRange())
        scroll.fitDocument()
        let container = try XCTUnwrap(view.textContainer)
        let manager = try XCTUnwrap(view.layoutManager)
        manager.ensureLayout(for: container)
        XCTAssertEqual(view.frame.width, scroll.contentView.bounds.width, accuracy: 0.5)
        XCTAssertEqual(container.containerSize.width, scroll.contentView.bounds.width - 2 * view.textContainerInset.width, accuracy: 0.5)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, used, _, _, _ in
            lines += 1
            XCTAssertLessThanOrEqual(used.maxX, container.containerSize.width + 1)
        }
        XCTAssertGreaterThan(lines, 2)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertGreaterThanOrEqual(view.frame.height, manager.usedRect(for: container).height + 2 * view.textContainerInset.height - 1)
    }

    func testFullListIsASeparateFixedWindowContainingANativeTable() throws {
        _ = store.create(content: EditorStyle.plain("A #work"))
        coordinator.openNewestNote()
        coordinator.showFullList()
        let window = try XCTUnwrap(coordinator.fullListWindow)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentView?.frame.size, WindowCoordinator.fullListSize)
        let table = try XCTUnwrap(find(NSTableView.self, in: try XCTUnwrap(window.contentView)))
        XCTAssertEqual(table.numberOfRows, 1)
    }

    func testEditingInFullListPersistsAndRefreshesNotepadWithoutStaleContent() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.showFullList()
        let host = try XCTUnwrap(coordinator.fullListWindow?.contentView)
        host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: host))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        host.layoutSubtreeIfNeeded()
        let tableEditor = try XCTUnwrap(find(DraftsTextView.self, in: host))
        tableEditor.insertText("Edited in the table #work", replacementRange: tableEditor.selectedRange())
        XCTAssertEqual(store.note(id)?.text, "Edited in the table #work")
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, id)
        XCTAssertEqual(coordinator.editor.textView?.string, "Edited in the table #work")
        XCTAssertFalse(coordinator.fullListWindow?.isVisible == true)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Edited in the table #work")
    }

    func testTrashPreservesNoteAndOpenFallsBackToNewestSurvivingNote() throws {
        coordinator.newBlank()
        let older = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Older note", replacementRange: NSRange(location: 0, length: 0))
        coordinator.newBlank()
        let newest = try XCTUnwrap(workspace.currentID)
        coordinator.trash(newest)
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, older)
        XCTAssertEqual(store.trashedNotes.map(\.id), [newest])
    }

    func testViewsRenderAtFixedSizes() throws {
        _ = store.create(content: EditorStyle.plain("Project ideas\nKeep it simple"))
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("An idea for later.\n\n• Keep it simple\n• Leave room to think")))
        workspace.currentID = note.id
        try render(ScratchpadView(store: store, workspace: workspace, preferences: preferences, editor: EditorBridge(), onSelect: { _ in }, onNoteList: {}, onDismissPicker: {}, onHide: {}, onNew: {}, onCopyAndClose: {}, onToggleExpansion: {}), size: WindowCoordinator.notepadSize, name: "scratchpad", checkCorners: true)
        workspace.pickerVisible = true
        try render(ScratchpadView(store: store, workspace: workspace, preferences: preferences, editor: EditorBridge(), onSelect: { _ in }, onNoteList: {}, onDismissPicker: {}, onHide: {}, onNew: {}, onCopyAndClose: {}, onToggleExpansion: {}), size: WindowCoordinator.notepadSize, name: "note-picker", checkCorners: true)
        workspace.closePicker()
        try render(FullListView(store: store, workspace: workspace, onOpen: { _ in }, onNew: {}, onSettings: {}, onTrash: { _ in }), size: WindowCoordinator.fullListSize, name: "full-list")
        try render(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store), size: NSSize(width: 520, height: 600), name: "settings")
        preferences.value.autoDeleteEnabled = true
        preferences.value.retentionAmount = 2
        preferences.value.retentionUnit = .hours
        try render(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store), size: NSSize(width: 520, height: 600), name: "settings-auto-delete")
    }

    func testRepeatedNewOnBlankNoteReusesSameSavedDraftAndFocusesEditor() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        for _ in 0..<15 { coordinator.newBlank(); XCTAssertEqual(workspace.currentID, id) }
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(NoteStore(directory: directory).notes.count, 1)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === coordinator.editor.textView)
    }

    func testCopyAndCloseCopiesWholeNoteNotSelectionAndKeepsSavedNote() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("First line\nSecond line", replacementRange: view.selectedRange())
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(coordinator.copyAndClose(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "First line\nSecond line")
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "First line\nSecond line")
        XCTAssertEqual(store.pendingCount, 0)
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, id)
    }

    func testCopyAndCloseKeyboardShortcutWorksWithoutChangingStandardCopy() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Copy this draft", replacementRange: view.selectedRange())
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        coordinator.editor.onCopyAndClose = { [weak self] in _ = self?.coordinator.copyAndClose(to: pasteboard) }
        let binding = LocalCommand.copyAndClose
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: binding.modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "C", charactersIgnoringModifiers: "C", isARepeat: false, keyCode: UInt16(binding.shortcut.keyCode)))
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertEqual(pasteboard.string(forType: .string), "Copy this draft")
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
    }

    func testCopyAndCloseWhenHiddenDoesNotOverwriteClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Leave clipboard alone", forType: .string)
        let count = pasteboard.changeCount
        XCTAssertFalse(coordinator.copyAndClose(to: pasteboard))
        XCTAssertEqual(pasteboard.changeCount, count)
    }

    func testAutoDeleteProtectsVisibleNoteButExpiresItAfterHiding() throws {
        let old = try XCTUnwrap(store.create(content: EditorStyle.plain("Expired note"), now: Date().addingTimeInterval(-120)))
        preferences.value.autoDeleteEnabled = true
        preferences.value.retentionAmount = 1
        preferences.value.retentionUnit = .minutes
        coordinator.open(old.id)
        coordinator.runCleanup()
        XCTAssertNotNil(store.note(old.id))
        coordinator.hideScratchpad()
        XCTAssertNil(store.note(old.id))
        XCTAssertNil(workspace.currentID)
    }

    func testCommandLShowsPickerInsideSameWindowAndFocusesSearch() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let event = try keyEvent(.noteList, in: panel)
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertTrue(workspace.pickerVisible)
        let (search, _) = try waitForPickerSearchField()
        XCTAssertTrue(search.window === panel)
        XCTAssertNotNil(search.currentEditor())
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(view.usesFindBar)
        XCTAssertEqual(view.frame.width, panel.contentView?.bounds.width)
    }

    func testCommandFExpandsOnCurrentDisplayAndRestoresExactFrameAndSelection() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Keep this selection and undo history", replacementRange: view.selectedRange())
        let selection = NSRange(location: 5, length: 4)
        view.setSelectedRange(selection)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + 20, y: panel.frame.minY + 15))
        let original = panel.frame
        let display = try XCTUnwrap(panel.screen).visibleFrame
        let event = try keyEvent(.toggleExpansion, in: panel)
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertEqual(panel.frame, display)
        XCTAssertTrue(workspace.notepadExpanded)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.string, "Keep this selection and undo history")
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(panel.frame, original)
        XCTAssertFalse(workspace.notepadExpanded)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertTrue(view.undoManager?.canUndo == true)
        XCTAssertEqual(store.activeNotes.count, 1)
    }

    func testExpansionAndListShortcutsWorkWhileSearchFieldHasFocus() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let original = panel.frame
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.noteList, in: panel)))
        let (_, fieldEditor) = try waitForPickerSearchField()
        workspace.pickerQuery = "preserve query"
        XCTAssertTrue(panel.firstResponder === fieldEditor)
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.toggleExpansion, in: panel)))
        XCTAssertTrue(workspace.notepadExpanded)
        XCTAssertTrue(workspace.pickerVisible)
        XCTAssertEqual(workspace.pickerQuery, "preserve query")
        XCTAssertTrue(panel.firstResponder === fieldEditor)
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.toggleExpansion, in: panel, repeatKey: true)))
        XCTAssertTrue(workspace.notepadExpanded, "Holding Command-F must not repeatedly toggle")
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.toggleExpansion, in: panel)))
        XCTAssertEqual(panel.frame, original)
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.noteList, in: panel)))
        XCTAssertEqual(workspace.pickerQuery, "preserve query")
    }

    func testReopeningAfterExpandedDismissalResetsToCompactSize() throws {
        coordinator.newBlank()
        coordinator.toggleExpansion()
        coordinator.dismissForExternalInteraction()
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertFalse(workspace.notepadExpanded)
        XCTAssertEqual(coordinator.scratchpad?.frame.size, WindowCoordinator.notepadSize)
        coordinator.toggleExpansion()
        coordinator.toggleExpansion()
        XCTAssertEqual(coordinator.scratchpad?.frame.size, WindowCoordinator.notepadSize)
    }

    func testIntegratedListSelectionKeepsExpandedFrameAndDoesNotCreateNotes() throws {
        let older = try XCTUnwrap(store.create(content: EditorStyle.plain("Older note")))
        coordinator.newBlank()
        coordinator.toggleExpansion()
        let expanded = try XCTUnwrap(coordinator.scratchpad).frame
        coordinator.showNotePicker()
        _ = try waitForPickerSearchField()
        coordinator.selectNote(older.id)
        XCTAssertTrue(workspace.notepadExpanded)
        XCTAssertEqual(coordinator.scratchpad?.frame, expanded)
        XCTAssertEqual(coordinator.editor.textView?.string, "Older note")
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertEqual(store.notes.count, 2)
    }

    func testOpeningSettingsSavesAndStopsNotepadAutoDismissal() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Before Settings", replacementRange: NSRange(location: 0, length: 0))
        coordinator.showSettings()
        let settings = try XCTUnwrap(NSApp.windows.first { $0.title == "Drafts — Settings" && $0.isVisible })
        defer { settings.close() }
        coordinator.handleMouseDown(in: nil)
        coordinator.handleApplicationActivation(processIdentifier: -1)
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Before Settings")
    }

    func testOutsideClickSavesHidesAndDismissesExpandedPicker() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.toggleExpansion()
        coordinator.showNotePicker()
        _ = try waitForPickerSearchField()
        store.update(id, content: EditorStyle.plain("Pending edits before outside click"))
        coordinator.handleMouseDown(in: nil)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Pending edits before outside click")
    }

    func testClicksAndFocusWithinNotepadDoNotHideIt() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        coordinator.handleMouseDown(in: panel)
        coordinator.showNotePicker()
        _ = try waitForPickerSearchField()
        coordinator.handleMouseDown(in: panel)
        coordinator.handleApplicationActivation(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(workspace.pickerVisible)
        coordinator.dismissNotePicker()
        XCTAssertTrue(panel.isVisible)
    }

    func testApplicationSwitchDismissesAndSavesButDoesNotCloseFullList() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Save on app switch", replacementRange: NSRange(location: 0, length: 0))
        coordinator.handleApplicationActivation(processIdentifier: -1)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Save on app switch")
        coordinator.showFullList()
        coordinator.handleApplicationActivation(processIdentifier: -1)
        XCTAssertTrue(coordinator.fullListWindow?.isVisible == true)
    }

    func testLosingKeyToAnotherWindowAutomaticallySavesWithoutStealingFocus() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Save on window switch", replacementRange: NSRange(location: 0, length: 0))
        // Like the notepad, this can take keyboard focus without activating the test runner.
        let other = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.coordinator.scratchpad?.isVisible == false
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertTrue(other.isKeyWindow)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Save on window switch")
    }

    func testFocusLossFailureKeepsNoteAndErrorSheetOpenUntilRetry() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        coordinator.editor.textView?.insertText("Never lose this", replacementRange: NSRange(location: 0, length: 0))
        coordinator.dismissForExternalInteraction()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.pendingCount, 1)
        let sheet = try XCTUnwrap(coordinator.scratchpad?.attachedSheet)
        coordinator.handleMouseDown(in: sheet)
        coordinator.dismissForExternalInteraction()
        XCTAssertTrue(coordinator.scratchpad?.attachedSheet === sheet)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        coordinator.scratchpad?.endSheet(sheet)
        try FileManager.default.removeItem(at: file)
        coordinator.dismissForExternalInteraction()
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Never lose this")
    }

    func testDeferredFocusLossCannotDismissANewlyReopenedNotepad() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        coordinator.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        coordinator.hideScratchpad()
        coordinator.openNewestNote()
        let settled = expectation(description: "Deferred focus callbacks have run")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        XCTAssertTrue(panel.isVisible)
    }

    private func keyEvent(_ command: LocalCommand, in window: NSWindow, repeatKey: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command.modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: command.key, charactersIgnoringModifiers: command.key, isARepeat: repeatKey, keyCode: UInt16(command.shortcut.keyCode)))
    }

    func testEscapeDismissesPickerBeforeHidingNoteAndRestoresEditorFocus() throws {
        coordinator.newBlank()
        coordinator.editor.textView?.insertText("Preserve the draft", replacementRange: NSRange(location: 0, length: 0))
        coordinator.showNotePicker()
        coordinator.scratchpad?.cancelOperation(nil)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === coordinator.editor.textView)
        XCTAssertEqual(coordinator.editor.textView?.string, "Preserve the draft")
        coordinator.scratchpad?.cancelOperation(nil)
        XCTAssertFalse(coordinator.scratchpad?.isVisible == true)
    }

    func testPickerSearchAndReturnOpenMatchingNote() throws {
        let older = try XCTUnwrap(store.create(content: EditorStyle.plain("Old project\nA distinct idea")))
        coordinator.newBlank()
        coordinator.showNotePicker()
        workspace.pickerQuery = "distinct"
        let (search, fieldEditor) = try waitForPickerSearchField()
        XCTAssertEqual(search.delegate?.control?(search, textView: fieldEditor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertEqual(workspace.currentID, older.id)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertEqual(coordinator.editor.textView?.string, "Old project\nA distinct idea")
        XCTAssertEqual(store.activeNotes.count, 2)
    }

    func testPickerArrowKeysNavigateAndReturnSelectsWithoutNewNotes() throws {
        let older = try XCTUnwrap(store.create(content: EditorStyle.plain("Older note")))
        coordinator.newBlank()
        coordinator.showNotePicker()
        let (search, fieldEditor) = try waitForPickerSearchField()
        XCTAssertEqual(search.delegate?.control?(search, textView: fieldEditor, doCommandBy: NSSelectorFromString("moveDown:")), true)
        XCTAssertEqual(search.delegate?.control?(search, textView: fieldEditor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertEqual(workspace.currentID, older.id)
        XCTAssertEqual(store.activeNotes.count, 2)
    }

    func testNoResultsDoesNotSwitchNotesAndDismissingRestoresSelection() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Keep this draft", replacementRange: view.selectedRange())
        let selection = NSRange(location: 5, length: 4)
        view.setSelectedRange(selection)
        coordinator.showNotePicker()
        workspace.pickerQuery = "no-matching-note"
        let (search, fieldEditor) = try waitForPickerSearchField()
        XCTAssertEqual(search.delegate?.control?(search, textView: fieldEditor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertTrue(workspace.pickerVisible)
        XCTAssertEqual(workspace.currentID, id)
        XCTAssertEqual(store.activeNotes.count, 1)
        XCTAssertEqual(search.delegate?.control?(search, textView: fieldEditor, doCommandBy: NSSelectorFromString("cancelOperation:")), true)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(coordinator.scratchpad?.firstResponder === view)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.string, "Keep this draft")
    }

    private func waitForPickerSearchField() throws -> (NoteSearchField, NSTextView) {
        let host = try XCTUnwrap(coordinator.scratchpad?.contentView)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            host.layoutSubtreeIfNeeded()
            return self?.find(NoteSearchField.self, in: host)?.currentEditor() is NSTextView
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "The picker should focus its native search editor")
        let field = try XCTUnwrap(find(NoteSearchField.self, in: host))
        return (field, try XCTUnwrap(field.currentEditor() as? NSTextView))
    }

    private func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let result = view as? V { return result }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    private func render<V: View>(_ view: V, size: NSSize, name: String, checkCorners: Bool = false) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        if checkCorners {
            for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0), (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.05)
            }
        }
        if let path = ProcessInfo.processInfo.environment["DRAFTS_PREVIEW_DIRECTORY"] {
            let destination = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: destination.appendingPathComponent("\(name).png"))
        }
    }
}
