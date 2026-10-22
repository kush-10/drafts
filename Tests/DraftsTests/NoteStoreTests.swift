import AppKit
import XCTest
@testable import Drafts

final class NoteStoreTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testNewEmptyNoteIsImmediatelySaved() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(now: now))
        let reloaded = NoteStore(directory: directory)
        XCTAssertEqual(reloaded.activeNotes.count, 1)
        XCTAssertEqual(reloaded.note(note.id)?.title, "Untitled note")
        XCTAssertEqual(try reloaded.note(note.id)?.attributedString().string, "")
    }

    func testLegacyRichTextIsNotDestructivelyMigrated() throws {
        let content = NSMutableAttributedString(attributedString: EditorStyle.plain("A heading\nBold and italic\nCode\nWebsite"))
        content.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 28), range: NSRange(location: 0, length: 9))
        content.addAttribute(.font, value: NSFontManager.shared.convert(EditorStyle.font, toHaveTrait: [.boldFontMask, .italicFontMask]), range: NSRange(location: 10, length: 15))
        content.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: NSRange(location: 26, length: 4))
        content.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 31, length: 7))
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(content: content, now: now))
        let loaded = try XCTUnwrap(NoteStore(directory: directory).note(note.id)).attributedString()
        XCTAssertEqual(loaded.string, content.string)
        let heading = try XCTUnwrap(loaded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(heading.pointSize, 28)
        let bold = try XCTUnwrap(loaded.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains([.boldFontMask, .italicFontMask]))
        XCTAssertNotNil(loaded.attribute(.link, at: 31, effectiveRange: nil))
    }

    func testExistingImageDataIsNotLostAfterUpgrade() throws {
        let content = try legacyImageContent()
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(content: content))
        let loaded = try XCTUnwrap(NoteStore(directory: directory).note(note.id)).attributedString()
        let attachment = try XCTUnwrap(loaded.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertNotNil(attachment.fileWrapper?.regularFileContents)
        XCTAssertTrue(note.matches("image"))
    }

    func testUpdatesPersistAndMoveToTop() throws {
        let store = NoteStore(directory: directory)
        let first = try XCTUnwrap(store.create(content: EditorStyle.plain("First"), now: now))
        _ = store.create(content: EditorStyle.plain("Second"), now: now.addingTimeInterval(1))
        store.update(first.id, content: EditorStyle.plain("Updated\nBody"), now: now.addingTimeInterval(2))
        XCTAssertEqual(store.activeNotes.first?.id, first.id)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertTrue(store.flush())
        XCTAssertEqual(store.pendingCount, 0)
        let reloaded = NoteStore(directory: directory)
        XCTAssertEqual(reloaded.note(first.id)?.text, "Updated\nBody")
        XCTAssertEqual(reloaded.note(first.id)?.updatedAt, now.addingTimeInterval(2))
    }

    func testSearchUsesAllWordsCaseAndDiacriticInsensitive() throws {
        let note = try Note.make(content: EditorStyle.plain("Café plans\nVisit PARIS this summer"))
        XCTAssertTrue(note.matches("cafe paris"))
        XCTAssertTrue(note.matches("   SUMMER  café "))
        XCTAssertTrue(note.matches(""))
        XCTAssertFalse(note.matches("cafe berlin"))
    }

    func testWordCountDoesNotCountBulletMarkersOrPunctuationAsWords() throws {
        let note = try Note.make(content: EditorStyle.plain("An idea for later.\n\n• Keep it simple\n• Leave room to think\n—"))
        XCTAssertEqual(note.wordCount, 11)
    }

    func testCleanupDisabledByDefault() throws {
        let store = NoteStore(directory: directory)
        let active = try XCTUnwrap(store.create(now: now.addingTimeInterval(-100 * 86_400)))
        let trashed = try XCTUnwrap(store.create(now: now.addingTimeInterval(-200 * 86_400)))
        store.trash(trashed.id, now: now.addingTimeInterval(-100 * 86_400))
        store.cleanup(preferences: Preferences(), now: now)
        XCTAssertNotNil(store.note(active.id))
        XCTAssertNotNil(store.note(trashed.id))
        XCTAssertEqual(store.notes.count, 2)
    }

    func testAutoDeleteUsesLastEditAndProtectsOpenNote() throws {
        let store = NoteStore(directory: directory)
        let old = now.addingTimeInterval(-40 * 86_400)
        let expired = try XCTUnwrap(store.create(now: old))
        let current = try XCTUnwrap(store.create(now: old))
        let edited = try XCTUnwrap(store.create(now: old))
        store.update(edited.id, content: EditorStyle.plain("Recently edited"), now: now)
        var prefs = Preferences()
        prefs.autoDeleteEnabled = true
        store.cleanup(preferences: prefs, excluding: current.id, now: now)
        XCTAssertNil(store.note(expired.id))
        XCTAssertEqual(Set(store.activeNotes.map(\.id)), Set([current.id, edited.id]))
        XCTAssertNil(NoteStore(directory: directory).note(expired.id))
    }

    func testCustomRetentionDeletesAtThresholdButNotBeforeIt() throws {
        let store = NoteStore(directory: directory)
        let expired = try XCTUnwrap(store.create(now: now.addingTimeInterval(-4 * 86_400)))
        let boundary = try XCTUnwrap(store.create(now: now.addingTimeInterval(-3 * 86_400)))
        let recent = try XCTUnwrap(store.create(now: now.addingTimeInterval(-3 * 86_400 + 1)))
        var prefs = Preferences()
        prefs.autoDeleteEnabled = true
        prefs.retentionAmount = 3
        store.cleanup(preferences: prefs, now: now)
        XCTAssertNil(store.note(expired.id))
        XCTAssertNil(store.note(boundary.id))
        XCTAssertNotNil(store.note(recent.id))
    }

    func testTrashUsesTheSameLastEditPolicyWithNoSeparateTimer() throws {
        let store = NoteStore(directory: directory)
        let old = try XCTUnwrap(store.create(now: now.addingTimeInterval(-8 * 86_400)))
        let recent = try XCTUnwrap(store.create(now: now.addingTimeInterval(-2 * 86_400)))
        store.trash(old.id, now: now)
        store.trash(recent.id, now: now)
        var prefs = Preferences()
        prefs.autoDeleteEnabled = true
        prefs.retentionAmount = 7
        store.cleanup(preferences: prefs, now: now)
        XCTAssertNil(store.note(old.id))
        XCTAssertNotNil(store.note(recent.id))
        XCTAssertNil(NoteStore(directory: directory).note(old.id))
    }

    func testRetentionSupportsMinutesAndHours() throws {
        let store = NoteStore(directory: directory)
        let expired = try XCTUnwrap(store.create(now: now.addingTimeInterval(-120)))
        let recent = try XCTUnwrap(store.create(now: now.addingTimeInterval(-60)))
        var prefs = Preferences()
        prefs.autoDeleteEnabled = true
        prefs.retentionAmount = 2
        prefs.retentionUnit = .minutes
        XCTAssertEqual(prefs.retentionInterval, 120)
        store.cleanup(preferences: prefs, now: now)
        XCTAssertNil(store.note(expired.id))
        XCTAssertNotNil(store.note(recent.id))
        prefs.retentionUnit = .hours
        XCTAssertEqual(prefs.retentionInterval, 7200)
    }

    func testNewDraftReusesBlankAndDoesNotCreateDuplicates() throws {
        let store = NoteStore(directory: directory)
        let first = try XCTUnwrap(store.newDraft())
        for _ in 0..<20 { XCTAssertEqual(store.newDraft(preferredID: first.id)?.id, first.id) }
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(NoteStore(directory: directory).notes.count, 1)
    }

    func testNewDraftFindsExistingWhitespaceBlankWithoutOverwritingContent() throws {
        let store = NoteStore(directory: directory)
        let blank = try XCTUnwrap(store.create(content: EditorStyle.plain(" \n\t ")))
        let filled = try XCTUnwrap(store.create(content: EditorStyle.plain("Keep this")))
        XCTAssertEqual(store.newDraft(preferredID: filled.id)?.id, blank.id)
        XCTAssertEqual(store.note(filled.id)?.text, "Keep this")
        XCTAssertEqual(store.notes.count, 2)
    }

    func testNewDraftDoesNotReuseTrashedBlanksOrLegacyImages() throws {
        let store = NoteStore(directory: directory)
        let blank = try XCTUnwrap(store.create())
        store.trash(blank.id)
        let image = try XCTUnwrap(store.create(content: legacyImageContent()))
        XCTAssertFalse(image.isBlank)
        let new = try XCTUnwrap(store.newDraft(preferredID: image.id))
        XCTAssertNotEqual(new.id, blank.id)
        XCTAssertNotEqual(new.id, image.id)
        XCTAssertTrue(new.isBlank)
    }

    func testPunctuationAndEmojiAreNotBlankEvenWithZeroWords() throws {
        XCTAssertFalse(try Note.make(content: EditorStyle.plain("…")).isBlank)
        XCTAssertFalse(try Note.make(content: EditorStyle.plain("🙂")).isBlank)
    }

    func testLegacyKeepFlagsLoadSafelyAndKeepAllDoesNotDeleteThem() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("Existing note"), now: now.addingTimeInterval(-100 * 86_400)))
        let url = directory.appendingPathComponent(note.id.uuidString).appendingPathExtension("json")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        legacy["keepForever"] = true
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let loaded = NoteStore(directory: directory)
        loaded.cleanup(preferences: Preferences(), now: now)
        XCTAssertEqual(loaded.note(note.id)?.text, "Existing note")
        var enabled = Preferences()
        enabled.autoDeleteEnabled = true
        loaded.cleanup(preferences: enabled, now: now)
        XCTAssertNil(loaded.note(note.id)) // The explicitly enabled policy has no per-note exceptions.
    }

    func testFailedSavePreventsAutoDeletionAndNewDraftCreation() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(now: now.addingTimeInterval(-100 * 86_400)))
        try FileManager.default.removeItem(at: directory)
        store.update(note.id, content: EditorStyle.plain("Unsaved content"), now: now.addingTimeInterval(-40 * 86_400))
        var prefs = Preferences()
        prefs.autoDeleteEnabled = true
        store.cleanup(preferences: prefs, now: now)
        XCTAssertEqual(store.note(note.id)?.text, "Unsaved content")
        XCTAssertNil(store.newDraft())
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testRestoreResetsRetentionAndPreservesContent() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("☐ Keep this\n☑ Done"), now: now.addingTimeInterval(-50 * 86_400)))
        store.trash(note.id, now: now)
        store.restore(note.id, now: now)
        XCTAssertNil(store.note(note.id)?.deletedAt)
        XCTAssertEqual(store.note(note.id)?.updatedAt, now)
        XCTAssertEqual(store.note(note.id)?.text, note.text)
        XCTAssertEqual(NoteStore(directory: directory).activeNotes.count, 1)
    }

    func testPermanentDeletionOnlyAcceptsTrashedNotes() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create())
        store.deletePermanently(note.id)
        XCTAssertNotNil(store.note(note.id))
        store.trash(note.id)
        store.deletePermanently(note.id)
        XCTAssertNil(store.note(note.id))
        XCTAssertTrue(NoteStore(directory: directory).notes.isEmpty)
    }

    func testMalformedFileIsNotOverwrittenOrDeleted() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("damaged.json")
        let data = Data("not JSON".utf8)
        try data.write(to: url)
        let store = NoteStore(directory: directory)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testSaveFailureKeepsPendingChangesForRetry() throws {
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create())
        try FileManager.default.removeItem(at: directory)
        store.update(note.id, content: EditorStyle.plain("Must not be lost"))
        XCTAssertFalse(store.flush())
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.note(note.id)?.text, "Must not be lost")
        XCTAssertNotNil(store.lastError)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(store.flush())
        XCTAssertEqual(NoteStore(directory: directory).note(note.id)?.text, "Must not be lost")
    }

    func testPreferencesPersistCustomTimesAndShortcuts() throws {
        let suite = "DraftsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.value.autoDeleteEnabled = true
        preferences.value.retentionAmount = 127
        preferences.value.retentionUnit = .hours
        preferences.value.openShortcut = Shortcut(keyCode: 0, modifiers: 2048, key: "A")
        XCTAssertEqual(PreferencesStore(defaults: defaults).value, preferences.value)
    }

    func testExplicitPasteDoesNotChangeClipboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Copied thought", forType: .string)
        let changeCount = pasteboard.changeCount
        let content = PasteContent.read(from: pasteboard)
        XCTAssertEqual(content?.string, "Copied thought")
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }
}
