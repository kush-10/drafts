import AppKit
import XCTest
@testable import Drafts

final class EditorTests: XCTestCase {
    private var view: DraftsTextView!
    private var bridge: EditorBridge!

    override func setUp() {
        _ = NSApplication.shared
        bridge = EditorBridge()
        view = DraftsTextView(frame: NSRect(x: 0, y: 0, width: 550, height: 400))
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.typingAttributes = EditorStyle.attributes
        view.editorBridge = bridge
        bridge.textView = view
    }

    override func tearDown() { view = nil; bridge = nil }

    private func setText(_ string: String) {
        view.textStorage?.setAttributedString(EditorStyle.plain(string))
        view.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        view.typingAttributes = EditorStyle.attributes
    }

    func testBoldAndItalicApplyToSelection() throws {
        setText("Make this bold")
        view.setSelectedRange(NSRange(location: 5, length: 9))
        bridge.toggleBold()
        bridge.toggleItalic()
        let font = try XCTUnwrap(view.attributedString().attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
        XCTAssertEqual(view.string, "Make this bold")
        bridge.toggleBold()
        let unbold = try XCTUnwrap(view.attributedString().attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: unbold).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: unbold).contains(.italicFontMask))
    }

    func testBoldTypingWithoutSelection() throws {
        setText("")
        bridge.toggleBold()
        let font = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testSettingsShortcutRemainsAvailableWithoutMenuBarIcon() throws {
        var openedSettings = false
        bridge.onSettings = { openedSettings = true }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43))
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertTrue(openedSettings)
    }

    func testRecreatedEditorReloadsSameNoteInsteadOfOpeningBlank() throws {
        let note = try Note.make(content: EditorStyle.plain("Do not lose this #work"))
        bridge.load(note)
        let replacement = DraftsTextView(frame: view.frame)
        replacement.isRichText = true
        bridge.textView = replacement
        replacement.editorBridge = bridge
        bridge.load(note)
        XCTAssertEqual(replacement.string, "Do not lose this #work")
        XCTAssertEqual(bridge.noteID, note.id)
    }

    func testUnderlineAppliesAndRemovesWithoutChangingText() {
        setText("Underline this")
        let range = NSRange(location: 0, length: 9)
        view.setSelectedRange(range)
        bridge.toggleUnderline()
        XCTAssertEqual(view.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(view.selectedRange(), range)
        bridge.toggleUnderline()
        XCTAssertNil(view.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(view.string, "Underline this")
    }

    func testUnderlineTypingWithoutSelection() {
        setText("")
        bridge.toggleUnderline()
        XCTAssertEqual(view.typingAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        bridge.toggleUnderline()
        XCTAssertNil(view.typingAttributes[.underlineStyle])
    }

    func testBulletsCanBeAddedAndRemovedAcrossParagraphs() {
        setText("One\nTwo\nThree")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        bridge.toggleBullets()
        XCTAssertEqual(view.string, "• One\n• Two\n• Three")
        bridge.toggleBullets()
        XCTAssertEqual(view.string, "One\nTwo\nThree")
    }

    func testBulletsDoNotSelectAndOverwriteCurrentParagraph() {
        setText("Keep this")
        bridge.toggleBullets()
        XCTAssertEqual(view.selectedRange(), NSRange(location: 11, length: 0))
        view.insertText(" too", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "• Keep this too")
    }

    func testBulletContinuationAndEmptyItemExit() {
        setText("• First")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "• First\n• ")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "• First\n")
    }

    func testNoChecklistContinuation() {
        setText("☐ Legacy text")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "☐ Legacy text\n")
    }

    func testBasicFormattingStripsHeadingsCodeLinksColorsAndImages() throws {
        let content = NSMutableAttributedString(string: "Text", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 28), .link: URL(string: "https://example.com")!,
            .backgroundColor: NSColor.white, .foregroundColor: NSColor.red,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        content.append(try legacyImageContent())
        let basic = EditorStyle.basicFormatting(content)
        XCTAssertEqual(basic.string, "Text")
        let font = try XCTUnwrap(basic.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 16)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertEqual(basic.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(basic.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertNil(basic.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(basic.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, EditorStyle.textColor)
        let code = EditorStyle.basicFormatting(NSAttributedString(string: "Code", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]))
        XCTAssertFalse((code.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    func testImageOnlyPasteLeavesExistingTextAndSelectionUntouched() throws {
        setText("Keep me")
        let selection = NSRange(location: 0, length: 7)
        view.setSelectedRange(selection)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let content = NSMutableAttributedString(attributedString: try legacyImageContent())
        content.append(EditorStyle.plain("\n"))
        pasteboard.setData(try Note.encode(content), forType: .rtfd)
        XCTAssertFalse(view.readSelection(from: pasteboard, type: .rtfd))
        XCTAssertEqual(view.string, "Keep me")
        XCTAssertEqual(view.selectedRange(), selection)
    }

    func testFormattingSupportsUndoAndRedo() throws {
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        setText("A thought")
        view.setSelectedRange(NSRange(location: 0, length: 9))
        window.undoManager?.removeAllActions()
        bridge.toggleUnderline()
        let undo = try XCTUnwrap(window.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertNil(view.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(view.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
    }

    func testKeyboardFormattingBindings() throws {
        setText("Text")
        view.setSelectedRange(NSRange(location: 0, length: 4))
        for binding in [LocalCommand.bold, .italic, .underline] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: binding.modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: binding.key, charactersIgnoringModifiers: binding.key, isARepeat: false, keyCode: UInt16(binding.shortcut.keyCode)))
            XCTAssertTrue(view.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(view.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let font = try XCTUnwrap(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
    }
}
