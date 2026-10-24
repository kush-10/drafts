import Carbon
import XCTest
@testable import Drafts

final class ShortcutTests: XCTestCase {
    func testOnlyTwoGlobalActionsAndLocalNoteCommands() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.openShortcut.label, "⌥Space")
        XCTAssertEqual(preferences.listShortcut.label, "⌥⇧L")
        XCTAssertEqual(preferences.shortcuts.count, 2)
        XCTAssertEqual(LocalCommand.allCases.filter { $0.group == .notes }, [.newNote, .copyAndClose, .noteList, .toggleExpansion])
        XCTAssertEqual(LocalCommand.newNote.label, "⌘N")
        XCTAssertEqual(LocalCommand.noteList.label, "⌘L")
        XCTAssertEqual(LocalCommand.noteList.title, "Integrated note list")
        XCTAssertEqual(LocalCommand.toggleExpansion.label, "⌘F")
        XCTAssertEqual(LocalCommand.copyAndClose.label, "⇧⌘C")
        XCTAssertFalse(LocalCommand.copyAndClose.shortcut.hasSameBinding(as: LocalCommand.copy.shortcut))
    }

    func testDuplicateBindingsAndFormattingConflictsAreRejected() {
        let preferences = Preferences()
        XCTAssertNotNil(preferences.shortcutConflict(preferences.openShortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.bold.shortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.copyAndClose.shortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.noteList.shortcut, replacing: \.openShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.toggleExpansion.shortcut, replacing: \.openShortcut))
        XCTAssertNil(preferences.shortcutConflict(preferences.listShortcut, replacing: \.listShortcut))
    }

    func testLocalCommandBindingsAreUnique() {
        let bindings = LocalCommand.allCases.map { "\($0.shortcut.keyCode):\($0.shortcut.modifiers)" }
        XCTAssertEqual(Set(bindings).count, bindings.count)
        XCTAssertEqual(LocalCommand.allCases.filter { $0.group == .formatting }, [.bold, .italic, .underline, .bullets])
    }

    func testMigrationPreservesIntervalButRequiresOptInToPermanentDeletion() throws {
        let old = Data("""
        {"keepOnTop":false,"cleanupEnabled":true,"retentionDays":17,"trashRetentionDays":8,
        "toggleShortcut":{"keyCode":0,"modifiers":2048,"key":"A"},
        "captureShortcut":{"keyCode":49,"modifiers":2560,"key":"Space"},
        "searchShortcut":{"keyCode":3,"modifiers":2560,"key":"F"}}
        """.utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(migrated.openShortcut, Preferences().openShortcut)
        XCTAssertEqual(migrated.listShortcut, Preferences().listShortcut)
        XCTAssertEqual(migrated.retentionAmount, 17)
        XCTAssertEqual(migrated.retentionUnit, .days)
        XCTAssertFalse(migrated.autoDeleteEnabled)
        XCTAssertFalse(migrated.keepOnTop)
        XCTAssertFalse(migrated.hideMenuBarIcon)
        let encoded = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["captureShortcut"])
        XCTAssertNil(object["newNoteShortcut"])
        XCTAssertNil(object["toggleShortcut"])
        XCTAssertNil(object["searchShortcut"])
        XCTAssertNil(object["trashRetentionDays"])
        XCTAssertNil(object["cleanupEnabled"])
        XCTAssertNotNil(object["openShortcut"])
        XCTAssertNotNil(object["listShortcut"])
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded), migrated)
    }

    func testHideMenuBarIconDefaultsToVisibleAndPersistsWhenEnabled() throws {
        XCTAssertFalse(Preferences().hideMenuBarIcon)
        var value = Preferences()
        value.hideMenuBarIcon = true
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)).hideMenuBarIcon)
    }
}
