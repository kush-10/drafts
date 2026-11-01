import Carbon
import AppKit
import XCTest
@testable import Drafts

private final class ShortcutMenuTarget: NSObject {
    var calls = 0
    @objc func invoke(_ sender: Any?) { calls += 1 }
}

final class ShortcutTests: XCTestCase {
    func testThreeDistinctGlobalActionsAndLocalNoteCommands() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.openShortcut.label, "⌥Space")
        XCTAssertEqual(preferences.listShortcut.label, "⌥⇧L")
        XCTAssertEqual(preferences.searchShortcut.label, "⌥⇧K")
        XCTAssertEqual(preferences.shortcuts.count, 3)
        XCTAssertEqual(LocalCommand.allCases.filter { $0.group == .notes }, [.newNote, .copyAndClose, .smartSearch, .toggleExpansion])
        XCTAssertEqual(LocalCommand.newNote.label, "⌘N")
        XCTAssertEqual(LocalCommand.smartSearch.label, "⌘K")
        XCTAssertFalse(LocalCommand.allCases.contains { ["l", "s"].contains($0.key) })
        XCTAssertEqual(LocalCommand.toggleExpansion.label, "⌘F")
        XCTAssertEqual(LocalCommand.copyAndClose.label, "⇧⌘C")
        XCTAssertFalse(LocalCommand.copyAndClose.shortcut.hasSameBinding(as: LocalCommand.copy.shortcut))
    }

    func testDuplicateBindingsAndFormattingConflictsAreRejected() {
        let preferences = Preferences()
        XCTAssertNotNil(preferences.shortcutConflict(preferences.openShortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.bold.shortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.copyAndClose.shortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.smartSearch.shortcut, replacing: \.openShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.toggleExpansion.shortcut, replacing: \.openShortcut))
        XCTAssertNil(preferences.shortcutConflict(preferences.listShortcut, replacing: \.listShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(preferences.searchShortcut, replacing: \.openShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(preferences.openShortcut, replacing: \.searchShortcut))
        XCTAssertNotNil(preferences.shortcutConflict(LocalCommand.smartSearch.shortcut, replacing: \.searchShortcut))
        XCTAssertNil(preferences.shortcutConflict(preferences.searchShortcut, replacing: \.searchShortcut))
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
        XCTAssertEqual(migrated.searchShortcut, Preferences().searchShortcut)
        XCTAssertNotNil(object["searchShortcut"])
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

    func testNewSearchBindingMigratesWithoutStealingExistingCustomShortcut() throws {
        var old = Preferences()
        old.openShortcut = old.searchShortcut
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "searchShortcut")
        let migrated = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.openShortcut, old.openShortcut)
        XCTAssertFalse(migrated.searchShortcut.hasSameBinding(as: migrated.openShortcut))
        XCTAssertFalse(migrated.searchShortcut.hasSameBinding(as: migrated.listShortcut))
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(migrated)), migrated)
    }

    func testGlobalSearchHotKeyDispatchesIndependently() {
        let manager = HotKeyManager()
        var actions: [String] = []
        manager.onOpen = { actions.append("open") }
        manager.onList = { actions.append("list") }
        manager.onSearch = { actions.append("search") }
        XCTAssertTrue(manager.handleHotKey(3))
        XCTAssertEqual(actions, ["search"])
        XCTAssertTrue(manager.handleHotKey(1))
        XCTAssertTrue(manager.handleHotKey(2))
        XCTAssertFalse(manager.handleHotKey(4))
        XCTAssertEqual(actions, ["search", "open", "list"])
    }

    func testControlOptionCommandListAndSearchAreAllowedAndPersist() throws {
        var preferences = Preferences()
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let list = Shortcut(keyCode: 37, modifiers: modifiers, key: "L")
        let search = Shortcut(keyCode: 40, modifiers: modifiers, key: "K")
        XCTAssertNil(preferences.shortcutConflict(list, replacing: \.listShortcut))
        preferences.listShortcut = list
        XCTAssertNil(preferences.shortcutConflict(search, replacing: \.searchShortcut))
        preferences.searchShortcut = search
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.listShortcut.label, "⌃⌥⌘L")
        XCTAssertEqual(restored.searchShortcut.label, "⌃⌥⌘K")
    }

    func testRecorderCapturesControlOptionCommandBeforeMenuAndUsesBaseKeyLabels() throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu
        let menu = NSMenu(), submenu = NSMenu(), root = NSMenuItem()
        let target = ShortcutMenuTarget()
        let item = NSMenuItem(title: "Conflicting menu command", action: #selector(ShortcutMenuTarget.invoke(_:)), keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.command, .option, .control]; item.target = target
        submenu.addItem(item); root.submenu = submenu; menu.addItem(root); NSApp.mainMenu = menu
        let panel = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 250, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let button = RecorderButton(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        panel.contentView = button
        var captured: [Shortcut] = [], recording: [Bool] = []
        button.onChange = { captured.append($0) }; button.onRecordingChange = { recording.append($0) }
        panel.makeKeyAndOrderFront(nil)
        defer { button.stopRecording(); panel.close(); NSApp.mainMenu = oldMenu }
        for (code, text, expected) in [(UInt16(37), "\u{c}", "L"), (UInt16(40), "\u{b}", "K")] {
            button.beginRecording()
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .control], timestamp: 0,
                                                     windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
            NSApp.sendEvent(event)
            XCTAssertFalse(button.recording)
            XCTAssertEqual(captured.last?.key, expected)
            XCTAssertEqual(captured.last?.keyCode, UInt32(code))
            XCTAssertEqual(captured.last?.modifiers, UInt32(cmdKey | optionKey | controlKey))
        }
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(target.calls, 0)
        XCTAssertEqual(recording, [true, false, true, false])
    }

    func testGlobalHotkeysSuspendWhileRecordingAndResumeWithNewBindings() throws {
        _ = NSApplication.shared
        let manager = HotKeyManager()
        var preferences = Preferences()
        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        preferences.openShortcut = Shortcut(keyCode: 31, modifiers: modifiers, key: "O")
        preferences.listShortcut = Shortcut(keyCode: 37, modifiers: modifiers, key: "L")
        preferences.searchShortcut = Shortcut(keyCode: 40, modifiers: modifiers, key: "K")
        manager.register(preferences)
        if let error = manager.error { throw XCTSkip("Test shortcuts unavailable in this desktop session: \(error)") }
        var calls = 0
        manager.onSearch = { calls += 1 }
        manager.setRecording(true)
        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(manager.handleHotKey(3)); XCTAssertEqual(calls, 0)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(40, modifiers, EventHotKeyID(signature: 0x54535444, id: 40), GetApplicationEventTarget(), 0, &reference)
        XCTAssertEqual(status, noErr, "The old global binding must be released while recording")
        if let reference { UnregisterEventHotKey(reference) }
        preferences.searchShortcut = Shortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey | controlKey), key: "K")
        manager.register(preferences)
        manager.setRecording(false)
        XCTAssertFalse(manager.isRecording); XCTAssertNil(manager.error)
        XCTAssertTrue(manager.handleHotKey(3)); XCTAssertEqual(calls, 1)
    }

    func testRecorderCancellationAndRemovalRestoreHotkeysWithoutChangingBinding() throws {
        _ = NSApplication.shared
        let panel = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 250, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let button = RecorderButton(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        panel.contentView = button
        var changes = 0, states: [Bool] = []
        button.onChange = { _ in changes += 1 }; button.onRecordingChange = { states.append($0) }
        panel.makeKeyAndOrderFront(nil)
        button.beginRecording()
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        button.keyDown(with: escape)
        XCTAssertFalse(button.recording)
        button.beginRecording()
        panel.contentView = NSView()
        XCTAssertFalse(button.recording)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(states, [true, false, true, false])
    }

    func testFailedGlobalRegistrationRetriesWithoutChangingPreferences() throws {
        _ = NSApplication.shared
        let manager = HotKeyManager()
        var preferences = Preferences()
        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        preferences.openShortcut = Shortcut(keyCode: 31, modifiers: modifiers, key: "O")
        preferences.listShortcut = Shortcut(keyCode: 37, modifiers: modifiers, key: "L")
        preferences.searchShortcut = Shortcut(keyCode: 40, modifiers: modifiers, key: "K")
        var blocker: EventHotKeyRef?
        let status = RegisterEventHotKey(40, modifiers, EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), 0, &blocker)
        guard status == noErr, let reference = blocker else { throw XCTSkip("Test shortcut unavailable: \(status)") }
        defer { if let blocker { UnregisterEventHotKey(blocker) } }
        manager.register(preferences)
        XCTAssertNotNil(manager.error)
        UnregisterEventHotKey(reference); blocker = nil
        manager.register(preferences)
        XCTAssertNil(manager.error, "Retry must register a previously failed binding even when preferences are unchanged")
        var probe: EventHotKeyRef?
        let probeStatus = RegisterEventHotKey(40, modifiers, EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), 0, &probe)
        if let probe { UnregisterEventHotKey(probe) }
        XCTAssertNotEqual(probeStatus, noErr, "The manager must now own the previously blocked shortcut")
    }

    func testCarbonEventsReachInstalledHandlerAndWindowActions() throws {
        _ = NSApplication.shared
        let manager = HotKeyManager()
        let panel = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 250, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        var actions: [String] = []
        manager.onList = { actions.append("list"); panel.makeKeyAndOrderFront(nil) }
        manager.onSearch = { actions.append("search"); panel.makeKeyAndOrderFront(nil) }
        func send(_ id: UInt32, signature: OSType = 0x44524654) throws -> OSStatus {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
            let carbonEvent = try XCTUnwrap(event)
            defer { ReleaseEvent(carbonEvent) }
            var identifier = EventHotKeyID(signature: signature, id: id)
            XCTAssertEqual(SetEventParameter(carbonEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
            return SendEventToEventTarget(carbonEvent, GetApplicationEventTarget())
        }
        XCTAssertEqual(try send(2), noErr)
        XCTAssertEqual(actions, ["list"])
        XCTAssertTrue(panel.isVisible)
        panel.orderOut(nil)
        XCTAssertEqual(try send(3), noErr)
        XCTAssertEqual(actions, ["list", "search"])
        XCTAssertTrue(panel.isVisible)
        manager.setRecording(true)
        XCTAssertEqual(try send(3), noErr)
        XCTAssertEqual(actions.count, 2)
        manager.setRecording(false)
        XCTAssertEqual(try send(3), noErr)
        XCTAssertEqual(actions.count, 3)
        XCTAssertNotEqual(try send(3, signature: 0x42414421), noErr)
        XCTAssertEqual(actions.count, 3)
    }
}
