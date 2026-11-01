import AppKit
import XCTest
@testable import Drafts

final class AppearanceAndTopicTests: XCTestCase {
    func testTopicCompletionMatchesPartialNamesAndUTF16Ranges() throws {
        let topics = TopicPolicy.definitions.map { NoteCategory(name: $0.name, description: $0.description) }
        let text = "🙏 Meeting /man"
        let completion = try XCTUnwrap(EditorTopicCompletion.find(in: text, selection: NSRange(location: text.utf16.count, length: 0), topics: topics))
        XCTAssertEqual(completion.topics.map(\.name), ["Mandir"])
        XCTAssertEqual((text as NSString).substring(with: completion.range), "/man")
        XCTAssertEqual(EditorTopicCompletion.find(in: "/", selection: NSRange(location: 1, length: 0), topics: topics)?.topics.count, 5)
        for ordinary in ["/Users/kush", "https://example.com/Dev", "//Dev", "word/Dev", "/unknown", "\\/Dev"] {
            XCTAssertNil(EditorTopicCompletion.find(in: ordinary, selection: NSRange(location: ordinary.utf16.count, length: 0), topics: topics))
        }
        XCTAssertNil(EditorTopicCompletion.find(in: "/Dev", selection: NSRange(location: 2, length: 0), topics: topics))
        XCTAssertNil(EditorTopicCompletion.find(in: "/Dev", selection: NSRange(location: 4, length: 1), topics: topics))
    }

    func testFontPreferencesMigrateClampAndRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(old.editorFontID, "system")
        XCTAssertEqual(old.editorFontSize, 16)
        let invalid = try JSONDecoder().decode(Preferences.self, from: Data("{\"editorFontID\":\"missing-font\",\"editorFontSize\":1000}".utf8))
        XCTAssertEqual(invalid.editorFontID, "system")
        XCTAssertEqual(invalid.editorFontSize, 40)
        var changed = old; changed.editorFontID = "monospaced"; changed.editorFontSize = 22
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed)), changed)
        XCTAssertEqual(EditorFontOption.clampedSize(.nan), 16)
        XCTAssertGreaterThanOrEqual(EditorFontOption.available.count, 6)
        XCTAssertEqual(EditorFontOption.font(id: "missing", size: 18).pointSize, 18)
    }

    func testFontAppearancePreservesTraitsAttachmentsAndOriginalContent() throws {
        let typography = EditorTypography.shared
        let oldID = typography.fontID, oldSize = typography.size
        defer { typography.select(fontID: oldID, size: oldSize) }
        let content = NSMutableAttributedString(string: "Bold italic", attributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 16), toHaveTrait: [.boldFontMask, .italicFontMask]),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        content.append(try legacyImageContent())
        let original = NSAttributedString(attributedString: content)
        typography.select(fontID: "monospaced", size: 23)
        let adapted = EditorStyle.adaptingToAppearance(content)
        let font = try XCTUnwrap(adapted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 23)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
        XCTAssertEqual(adapted.string, original.string)
        XCTAssertNotNil(adapted.attribute(.attachment, at: adapted.length - 1, effectiveRange: nil))
        XCTAssertEqual(adapted.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(content, original)
    }
}
