import AppKit
import XCTest
@testable import Drafts

final class NoteSearchTests: XCTestCase {
    func testSearchIsPlainTextAndDoesNotTreatHashtagsSpecially() throws {
        let note = try Note.make(content: EditorStyle.plain("Trip to Paris #workshop"))
        XCTAssertTrue(note.matches("#work"))
        XCTAssertTrue(note.matches("#WORK PARIS"))
        XCTAssertTrue(note.matches("#"))
        XCTAssertFalse(note.matches("#home"))
    }

    func testExistingHashTextIsPreservedWithoutMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftsSearchTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        let note = try XCTUnwrap(store.create(content: EditorStyle.plain("Keep #existing text intact")))
        XCTAssertEqual(try NoteStore(directory: directory).note(note.id)?.attributedString().string, "Keep #existing text intact")
    }
}
