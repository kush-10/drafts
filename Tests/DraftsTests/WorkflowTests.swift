import AppKit
import Carbon
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
        coordinator?.intelligence.shutdown()
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

    func testNotesTableRendersWithoutCreatingOrdinaryNotes() throws {
        coordinator.showFullList()
        let window = try XCTUnwrap(coordinator.scratchpad)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(store.notes.isEmpty)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 640)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 380)
        XCTAssertTrue(store.notes.isEmpty)
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

    func testShortcutHidesAndFlushesPendingEditsBeforeReopeningLatestEditedNote() throws {
        let older = try XCTUnwrap(store.create(content: EditorStyle.plain("Older"), now: Date().addingTimeInterval(-200)))
        _ = try XCTUnwrap(store.create(content: EditorStyle.plain("Newest"), now: Date().addingTimeInterval(-100)))
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
        XCTAssertEqual(workspace.currentID, older.id)
        XCTAssertEqual(view.string, "Edited older")
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

    func testOpenChoosesMostRecentlyEditedNotNewestCreatedOrSelected() throws {
        let old = try XCTUnwrap(store.create(content: EditorStyle.plain("Older"), now: Date().addingTimeInterval(-200)))
        let newest = try XCTUnwrap(store.create(content: EditorStyle.plain("Newest"), now: Date().addingTimeInterval(-100)))
        store.update(old.id, content: EditorStyle.plain("Edited just now"))
        coordinator.open(newest.id)
        coordinator.openNewestNote()
        XCTAssertEqual(workspace.currentID, old.id)
        XCTAssertEqual(coordinator.editor.textView?.string, "Edited just now")
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

    func testReopeningRemembersSizeButRecentresWindow() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let original = panel.frame
        XCTAssertEqual(original.size, WindowCoordinator.notepadSize)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        panel.setFrameOrigin(NSPoint(x: original.minX + 75, y: original.minY + 50))
        panel.setContentSize(NSSize(width: 850, height: 550))
        coordinator.hideScratchpad()
        coordinator.openNewestNote()
        XCTAssertEqual(panel.frame.size, NSSize(width: 850, height: 550))
        XCTAssertEqual(panel.frame.midX, original.midX)
        XCTAssertEqual(panel.frame.midY, original.midY)
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

    func testFullListUsesSameResizableWindowAndSupportsMultiSelection() throws {
        _ = store.create(content: EditorStyle.plain("A #work"))
        _ = store.create(content: EditorStyle.plain("B #home"))
        coordinator.openNewestNote()
        let original = try XCTUnwrap(coordinator.scratchpad)
        let frame = original.frame
        coordinator.showFullList()
        let window = try XCTUnwrap(coordinator.scratchpad)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window === original)
        XCTAssertTrue(workspace.tableVisible)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.frame, frame)
        let table = try XCTUnwrap(find(NSTableView.self, in: try XCTUnwrap(window.contentView)))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertTrue(table.allowsMultipleSelection)
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(workspace.tableSelection.count, 2)
    }

    func testDragHandleStaysAtTopInEditorAndTableWithoutCoveringEditor() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let host = try XCTUnwrap(panel.contentView)
        for tableVisible in [false, true] {
            if tableVisible { coordinator.showFullList() }
            host.layoutSubtreeIfNeeded()
            let handle = try XCTUnwrap(find(WindowDragRegion.DragView.self, in: host))
            let frame = handle.convert(handle.bounds, to: nil)
            XCTAssertEqual(frame.maxY, panel.contentLayoutRect.maxY, accuracy: 1)
            XCTAssertEqual(frame.height, 44, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.width, 96)
            XCTAssertTrue(handle.hitTest(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY)) === handle)
            if !tableVisible {
                let scroll = try XCTUnwrap(coordinator.editor.textView?.enclosingScrollView)
                let editorFrame = scroll.convert(scroll.bounds, to: nil)
                XCTAssertLessThanOrEqual(editorFrame.maxY, frame.minY + 1)
            }
        }
    }

    func testOpeningLongNoteRevealsFinalEmptyLineWithoutTyping() throws {
        let text = (0..<100).map { "Line \($0)" }.joined(separator: "\n") + "\n"
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain(text)))
        coordinator.open(note.id)
        let view = try XCTUnwrap(coordinator.editor.textView)
        let scroll = try XCTUnwrap(view.enclosingScrollView as? EditorScrollView)
        settleEditorLayout()
        XCTAssertEqual(view.selectedRange(), NSRange(location: text.utf16.count, length: 0))
        XCTAssertTrue(scroll.isCaretVisible)
        let caret = try XCTUnwrap(scroll.caretRect)
        XCTAssertGreaterThanOrEqual(scroll.documentVisibleRect.maxY - caret.maxY, EditorScrollView.caretBottomPadding - 1)
        XCTAssertEqual(view.string, text)
        XCTAssertEqual(store.note(note.id)?.updatedAt, note.updatedAt)
    }

    func testKeyboardNavigationToBottomRevealsCaretBeforeAnyEdit() throws {
        let text = (0..<100).map { "Line \($0)" }.joined(separator: "\n")
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain(text)))
        coordinator.open(note.id)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let view = try XCTUnwrap(coordinator.editor.textView)
        let scroll = try XCTUnwrap(view.enclosingScrollView as? EditorScrollView)
        settleEditorLayout()
        view.moveToBeginningOfDocument(nil)
        settleEditorLayout()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                  windowNumber: panel.windowNumber, context: nil, characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125))
        view.keyDown(with: event)
        settleEditorLayout()
        XCTAssertEqual(view.selectedRange().location, text.utf16.count)
        XCTAssertTrue(scroll.isCaretVisible)
        XCTAssertEqual(view.string, text)
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testResizeAndFontChangeKeepVisibleBottomCaretInView() throws {
        let text = (0..<90).map { "A longer line \($0) that wraps when the window becomes narrower." }.joined(separator: "\n") + "\n"
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain(text)))
        coordinator.open(note.id)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let view = try XCTUnwrap(coordinator.editor.textView)
        let scroll = try XCTUnwrap(view.enclosingScrollView as? EditorScrollView)
        settleEditorLayout()
        XCTAssertTrue(scroll.isCaretVisible)
        panel.setContentSize(NSSize(width: 640, height: 380))
        settleEditorLayout()
        XCTAssertTrue(scroll.isCaretVisible)
        preferences.value.editorFontSize = 30
        defer { preferences.value.editorFontSize = 16 }
        coordinator.editor.applyAppearance()
        settleEditorLayout()
        XCTAssertTrue(scroll.isCaretVisible)
        XCTAssertEqual(view.selectedRange().location, text.utf16.count)
        XCTAssertEqual(store.note(note.id)?.updatedAt, note.updatedAt)
    }

    func testManualScrollIsNotUndoneByLayoutAutosaveOrAppearanceUpdates() throws {
        let text = (0..<100).map { "Line \($0)" }.joined(separator: "\n")
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain(text)))
        coordinator.open(note.id)
        let view = try XCTUnwrap(coordinator.editor.textView)
        let scroll = try XCTUnwrap(view.enclosingScrollView as? EditorScrollView)
        settleEditorLayout()
        view.scroll(NSPoint.zero)
        let top = scroll.contentView.bounds.origin
        XCTAssertFalse(scroll.isCaretVisible)
        XCTAssertTrue(store.flush())
        coordinator.editor.load(try XCTUnwrap(store.note(note.id)))
        preferences.value.editorFontSize = 18
        defer { preferences.value.editorFontSize = 16 }
        coordinator.editor.applyAppearance()
        settleEditorLayout()
        XCTAssertEqual(scroll.contentView.bounds.origin.y, top.y, accuracy: 1)
        XCTAssertFalse(scroll.isCaretVisible)
        XCTAssertEqual(view.selectedRange().location, text.utf16.count)
    }

    private func settleEditorLayout() {
        coordinator.scratchpad?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        coordinator.scratchpad?.contentView?.layoutSubtreeIfNeeded()
    }

    func testOpeningTableRowReturnsToEditorAndPreservesTableState() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.showFullList()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let host = try XCTUnwrap(panel.contentView)
        host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: host))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        coordinator.selectNote(id)
        let editor = try XCTUnwrap(coordinator.editor.textView)
        editor.insertText("Edited after opening row", replacementRange: editor.selectedRange())
        XCTAssertTrue(store.flush())
        XCTAssertEqual(workspace.currentID, id)
        XCTAssertFalse(workspace.tableVisible)
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Edited after opening row")
        workspace.tableQuery = "Edited"; workspace.tableSelection = [id]
        coordinator.showFullList()
        XCTAssertTrue(coordinator.scratchpad === panel)
        XCTAssertEqual(workspace.tableQuery, "Edited")
        XCTAssertEqual(workspace.tableSelection, [id])
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
        try render(FullListView(store: store, workspace: workspace, onOpen: { _ in }, onNew: {}, onBack: {}, categories: coordinator.intelligence.categories), size: WindowCoordinator.notepadSize, name: "all-notes")
        try render(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store), size: NSSize(width: 520, height: 600), name: "settings")
        preferences.value.autoDeleteEnabled = true
        preferences.value.retentionAmount = 2
        preferences.value.retentionUnit = .hours
        try render(SettingsView(preferences: preferences, hotKeys: hotKeys, store: store), size: NSSize(width: 520, height: 600), name: "settings-auto-delete")
        let intelligence = coordinator.intelligence
        try render(IntelligenceSettings(intelligence: intelligence, preferences: preferences).font(.system(size: 12)).padding(20).background(DraftsTheme.surface), size: NSSize(width: 520, height: 800), name: "ai-topics-settings")
        intelligence.categories.setManual(intelligence.categories.categories[0].id, noteID: note.id, included: true)
        workspace.smartPicker = true
        workspace.pickerVisible = true
        workspace.pickerQuery = "/Mandir"
        try render(ScratchpadView(store: store, workspace: workspace, preferences: preferences, editor: EditorBridge(), onSelect: { _ in }, onNoteList: {}, onDismissPicker: {}, onHide: {}, onNew: {}, onCopyAndClose: {}, onToggleExpansion: {}, intelligence: intelligence), size: WindowCoordinator.notepadSize, name: "smart-search", checkCorners: true)
        workspace.closePicker()
        preferences.value.themeID = "latte"
        try render(ScratchpadView(store: store, workspace: workspace, preferences: preferences, editor: EditorBridge(), onSelect: { _ in }, onNoteList: {}, onDismissPicker: {}, onHide: {}, onNew: {}, onCopyAndClose: {}, onToggleExpansion: {}, intelligence: intelligence), size: WindowCoordinator.notepadSize, name: "latte-notepad", checkCorners: true)
        try render(ThemeChooser(preferences: preferences).padding(20).background(DraftsTheme.surface), size: NSSize(width: 520, height: 580), name: "themes")
        preferences.value.themeID = "charcoal"
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

    func testCommandKShowsPickerInsideSameWindowAndFocusesSearch() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let event = try keyEvent(.smartSearch, in: panel)
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertTrue(workspace.pickerVisible)
        let (search, _) = try waitForPickerSearchField()
        XCTAssertTrue(search.window === panel)
        XCTAssertNotNil(search.currentEditor())
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(view.usesFindBar)
        XCTAssertEqual(view.frame.width, panel.contentView?.bounds.width)
    }

    func testEditorSlashTopicIsAssignedRemovedSavedAndRemembered() throws {
        preferences.value.autoOrganise = false
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        let id = try XCTUnwrap(workspace.currentID)
        view.insertText("Meeting /man", replacementRange: view.selectedRange())
        XCTAssertEqual(coordinator.editor.topicCompletion?.topics.map(\.name), ["Mandir"])
        view.insertTab(nil)
        XCTAssertEqual(view.string, "Meeting ")
        XCTAssertEqual(coordinator.intelligence.categories.names(for: id), "Mandir")
        view.insertText("/Prompt", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "Meeting ")
        XCTAssertEqual(coordinator.intelligence.categories.names(for: id), "Mandir, Prompt")
        XCTAssertTrue(store.flush())
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Meeting ")
        XCTAssertEqual(coordinator.intelligence.memory.count, 1)
    }

    func testEscapeDismissesEditorTopicSuggestionsWithoutHidingOrRemovingText() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("/Dev", replacementRange: view.selectedRange())
        XCTAssertNotNil(coordinator.editor.topicCompletion)
        view.cancelOperation(nil)
        XCTAssertNil(coordinator.editor.topicCompletion)
        XCTAssertEqual(view.string, "/Dev")
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "/Dev\n")
    }

    func testSlashTopicUndoAndRedoRestoreBothTextAndManualAssignment() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        let id = try XCTUnwrap(workspace.currentID)
        view.insertText("Keep /Dev", replacementRange: view.selectedRange())
        let undo = try XCTUnwrap(view.undoManager)
        undo.removeAllActions()
        view.insertTab(nil)
        XCTAssertEqual(view.string, "Keep ")
        XCTAssertEqual(coordinator.intelligence.categories.names(for: id), "Dev")
        undo.undo()
        XCTAssertEqual(view.string, "Keep /Dev")
        XCTAssertTrue(coordinator.intelligence.categories.labels(for: id).included.isEmpty)
        undo.redo()
        XCTAssertEqual(view.string, "Keep ")
        XCTAssertEqual(coordinator.intelligence.categories.names(for: id), "Dev")
    }

    func testSettingsPagesRenderAtTheirWindowSize() throws {
        for page in SettingsPage.allCases {
            let content = NSHostingView(rootView: SettingsView(preferences: preferences, hotKeys: hotKeys, store: store, intelligence: coordinator.intelligence, initialPage: page))
            content.frame = NSRect(x: 0, y: 0, width: 820, height: 640)
            content.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 820)
            XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 640)
            if let output = ProcessInfo.processInfo.environment["DRAFTS_TEST_SNAPSHOTS"] {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings-\(page.id).png"))
            }
        }
    }

    func testFontChangeUpdatesEditorWithoutChangingSavedNoteSelectionOrUndo() throws {
        coordinator.newBlank()
        let view = try XCTUnwrap(coordinator.editor.textView)
        let id = try XCTUnwrap(workspace.currentID)
        view.insertText("Keep this thought", replacementRange: view.selectedRange())
        XCTAssertTrue(store.flush())
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        let original = try Data(contentsOf: url)
        let selection = NSRange(location: 5, length: 4)
        view.setSelectedRange(selection)
        coordinator.editor.toggleBold()
        XCTAssertTrue(store.flush())
        let afterFormatting = try Data(contentsOf: url)
        XCTAssertNotEqual(afterFormatting, original)
        let timestamp = store.note(id)?.updatedAt
        preferences.value.editorFontID = "monospaced"
        preferences.value.editorFontSize = 22
        coordinator.editor.applyAppearance()
        let font = try XCTUnwrap(view.attributedString().attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 22)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertEqual(view.string, "Keep this thought")
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(store.note(id)?.updatedAt, timestamp)
        XCTAssertEqual(try Data(contentsOf: url), afterFormatting)
        XCTAssertTrue(view.undoManager?.canUndo == true)
        preferences.value.editorFontID = "system"; preferences.value.editorFontSize = 16
    }

    func testCarbonListAndSearchEventsOpenIntegratedViewsFromHiddenWindow() throws {
        hotKeys.onList = { [weak self] in self?.coordinator.showFullList() }
        hotKeys.onSearch = { [weak self] in self?.coordinator.showGlobalSearch() }
        func send(_ id: UInt32) throws {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
            let carbonEvent = try XCTUnwrap(event)
            defer { ReleaseEvent(carbonEvent) }
            var identifier = EventHotKeyID(signature: 0x44524654, id: id)
            XCTAssertEqual(SetEventParameter(carbonEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
            XCTAssertEqual(SendEventToEventTarget(carbonEvent, GetApplicationEventTarget()), noErr)
        }
        try send(2)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(workspace.tableVisible)
        coordinator.hideScratchpad()
        try send(3)
        XCTAssertTrue(coordinator.scratchpad === panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(workspace.pickerVisible)
        let (search, _) = try waitForPickerSearchField()
        XCTAssertNotNil(search.currentEditor())
        XCTAssertTrue(store.notes.isEmpty, "Global navigation must not create notes")
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
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.smartSearch, in: panel)))
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
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.smartSearch, in: panel)))
        XCTAssertEqual(workspace.pickerQuery, "preserve query")
    }

    func testReopeningRemembersExpansionAndCanRestoreCompactSize() throws {
        coordinator.newBlank()
        coordinator.toggleExpansion()
        coordinator.hideScratchpad()
        coordinator.toggleScratchpad()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(workspace.notepadExpanded)
        XCTAssertEqual(coordinator.scratchpad?.frame, coordinator.scratchpad?.screen?.visibleFrame)
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

    func testOutsideClickKeepsExpandedPickerAndPendingEditsOpen() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.toggleExpansion()
        coordinator.showNotePicker()
        _ = try waitForPickerSearchField()
        store.update(id, content: EditorStyle.plain("Pending edits before outside click"))
        coordinator.handleMouseDown(in: nil)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(workspace.pickerVisible)
        XCTAssertTrue(workspace.notepadExpanded)
        XCTAssertEqual(store.note(id)?.text, "Pending edits before outside click")
        XCTAssertTrue(store.flush())
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

    func testRepeatedSearchKeepsTheSameFieldQueryAndSelection() throws {
        coordinator.newBlank()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let frame = panel.frame
        let editor = try XCTUnwrap(coordinator.editor.textView)
        editor.insertText("A useful draft", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 2, length: 6))
        XCTAssertTrue(editor.performKeyEquivalent(with: try keyEvent(.smartSearch, in: panel)))
        XCTAssertTrue(workspace.smartPicker)
        let (field, _) = try waitForPickerSearchField()
        XCTAssertEqual(field.placeholderString, "Search notes and topics")
        field.stringValue = "useful"
        workspace.pickerQuery = "useful"
        panel.contentView?.layoutSubtreeIfNeeded()
        let fieldEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let selection = NSRange(location: 2, length: 2)
        fieldEditor.setSelectedRange(selection)
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.smartSearch, in: panel)))
        XCTAssertTrue(workspace.smartPicker)
        let (sameField, _) = try waitForPickerSearchField()
        XCTAssertTrue(sameField === field)
        XCTAssertEqual(workspace.pickerQuery, "useful")
        XCTAssertEqual(fieldEditor.selectedRange(), selection)
        XCTAssertTrue(panel.performKeyEquivalent(with: try keyEvent(.smartSearch, in: panel)))
        XCTAssertTrue(workspace.smartPicker)
        _ = try waitForPickerSearchField()
        coordinator.cancelNotepad()
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 6))
        XCTAssertEqual(panel.frame, frame)
    }

    func testGlobalSearchOpensHiddenWindowWithoutCreatingANote() throws {
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("Find this specific note")))
        coordinator.showGlobalSearch()
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let (field, fieldEditor) = try waitForPickerSearchField()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(workspace.pickerVisible)
        XCTAssertTrue(workspace.smartPicker)
        XCTAssertEqual(store.notes.count, 1)
        workspace.pickerQuery = "specific"
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(field.delegate?.control?(field, textView: fieldEditor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertEqual(workspace.currentID, note.id)
        XCTAssertFalse(workspace.pickerVisible)
        XCTAssertTrue(panel.firstResponder === coordinator.editor.textView)
        coordinator.hideScratchpad()
        coordinator.showGlobalSearch()
        _ = try waitForPickerSearchField()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(workspace.pickerQuery, "")
    }

    func testGlobalSearchOnEmptyCollectionDoesNotCreateBlankDraft() throws {
        coordinator.showGlobalSearch()
        _ = try waitForPickerSearchField()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(workspace.pickerVisible)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNil(workspace.currentID)
    }

    func testRepeatedGlobalSearchKeepsExpandedFrameAndQuery() throws {
        coordinator.newBlank()
        coordinator.toggleExpansion()
        coordinator.showGlobalSearch()
        let (field, _) = try waitForPickerSearchField()
        workspace.pickerQuery = "some idea"
        let frame = try XCTUnwrap(coordinator.scratchpad).frame
        coordinator.showGlobalSearch()
        let (sameField, _) = try waitForPickerSearchField()
        XCTAssertTrue(field === sameField)
        XCTAssertEqual(workspace.pickerQuery, "some idea")
        XCTAssertEqual(coordinator.scratchpad?.frame, frame)
        XCTAssertTrue(workspace.notepadExpanded)
    }

    func testAutocompleteInsertsFixedTopicWithoutQuotesAndFiltersResults() throws {
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("Project design")))
        _ = store.create(content: EditorStyle.plain("Other design"))
        let categories = coordinator.intelligence.categories
        let topic = try XCTUnwrap(categories.categories.first { $0.name == "University" })
        categories.setManual(topic.id, noteID: note.id, included: true)
        coordinator.showGlobalSearch()
        workspace.pickerQuery = "/Uni"
        let (field, editor) = try waitForPickerSearchField()
        XCTAssertEqual(field.delegate?.control?(field, textView: editor, doCommandBy: NSSelectorFromString("insertTab:")), true)
        XCTAssertEqual(workspace.pickerQuery, "/University ")
        XCTAssertFalse(workspace.pickerQuery.contains("\""))
        workspace.pickerQuery += "design"
        coordinator.scratchpad?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(field.delegate?.control?(field, textView: editor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertEqual(workspace.currentID, note.id)
        XCTAssertFalse(workspace.pickerVisible)
    }

    func testSmartCategorySearchFiltersNotesWithoutNeedingModel() throws {
        let work = try XCTUnwrap(store.create(content: EditorStyle.plain("A work project")))
        _ = store.create(content: EditorStyle.plain("A holiday project"))
        let categories = coordinator.intelligence.categories
        categories.setManual(categories.categories[0].id, noteID: work.id, included: true)
        coordinator.openNewestNote()
        coordinator.showSmartSearch()
        workspace.pickerQuery = "/Mandir project"
        let (field, fieldEditor) = try waitForPickerSearchField()
        XCTAssertEqual(field.delegate?.control?(field, textView: fieldEditor, doCommandBy: NSSelectorFromString("insertNewline:")), true)
        XCTAssertEqual(workspace.currentID, work.id)
        XCTAssertFalse(workspace.pickerVisible)
    }

    func testThemeChangePreservesTextSelectionUndoAndEditTimestamp() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let panel = try XCTUnwrap(coordinator.scratchpad)
        let view = try XCTUnwrap(coordinator.editor.textView)
        view.insertText("Keep my text and undo", replacementRange: view.selectedRange())
        let selection = NSRange(location: 5, length: 7)
        view.setSelectedRange(selection)
        let edited = store.note(id)?.updatedAt
        preferences.value.themeID = "latte"
        panel.contentView?.layoutSubtreeIfNeeded()
        coordinator.editor.applyAppearance()
        XCTAssertEqual(panel.appearance?.name, .aqua)
        XCTAssertEqual(view.string, "Keep my text and undo")
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertTrue(view.undoManager?.canUndo == true)
        XCTAssertEqual(store.note(id)?.updatedAt, edited)
        XCTAssertEqual(view.typingAttributes[.foregroundColor] as? NSColor, EditorStyle.textColor)
        preferences.value.themeID = "charcoal"
    }

    func testExpiredSizeMemoryResetsAndNewNotePreservesVisibleExpansion() throws {
        coordinator.newBlank()
        coordinator.toggleExpansion()
        let frame = try XCTUnwrap(coordinator.scratchpad).frame
        coordinator.editor.textView?.insertText("Nonblank", replacementRange: NSRange(location: 0, length: 0))
        coordinator.newBlank()
        XCTAssertEqual(coordinator.scratchpad?.frame, frame)
        XCTAssertTrue(workspace.notepadExpanded)
        coordinator.hideScratchpad()
        workspace.rememberWindow(frame: frame, expanded: true, restoreFrame: nil, now: Date().addingTimeInterval(-1801))
        coordinator.openNewestNote()
        XCTAssertFalse(workspace.notepadExpanded)
        XCTAssertEqual(coordinator.scratchpad?.frame.size, WindowCoordinator.notepadSize)
    }

    func testApplicationSwitchDoesNotHideNotepadOrFullList() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Save on app switch", replacementRange: NSRange(location: 0, length: 0))
        coordinator.handleApplicationActivation(processIdentifier: -1)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(store.flush())
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Save on app switch")
        coordinator.showFullList()
        coordinator.handleApplicationActivation(processIdentifier: -1)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(workspace.tableVisible)
    }

    func testLosingKeyKeepsNotepadVisibleWithoutStealingFocus() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        coordinator.editor.textView?.insertText("Save on window switch", replacementRange: NSRange(location: 0, length: 0))
        // Like the notepad, this can take keyboard focus without activating the test runner.
        let other = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        let settled = expectation(description: "Focus callbacks completed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertTrue(other.isKeyWindow)
        XCTAssertTrue(store.flush())
        XCTAssertEqual(NoteStore(directory: directory).note(id)?.text, "Save on window switch")
    }

    func testExplicitHideFailureKeepsNoteAndErrorSheetOpenUntilRetry() throws {
        coordinator.newBlank()
        let id = try XCTUnwrap(workspace.currentID)
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        coordinator.editor.textView?.insertText("Never lose this", replacementRange: NSRange(location: 0, length: 0))
        coordinator.dismissForExternalInteraction()
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertNil(coordinator.scratchpad?.attachedSheet)
        coordinator.hideScratchpad()
        let sheet = try XCTUnwrap(coordinator.scratchpad?.attachedSheet)
        coordinator.handleMouseDown(in: sheet)
        coordinator.dismissForExternalInteraction()
        XCTAssertTrue(coordinator.scratchpad?.attachedSheet === sheet)
        XCTAssertTrue(coordinator.scratchpad?.isVisible == true)
        coordinator.scratchpad?.endSheet(sheet)
        try FileManager.default.removeItem(at: file)
        coordinator.hideScratchpad()
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
        let host = NSHostingView(rootView: view.environment(\.colorScheme, DraftsTheme.palette.scheme))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = DraftsTheme.palette.appearance
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
