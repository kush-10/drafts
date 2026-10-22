import AppKit
import XCTest

// Compatibility fixture only: the app no longer creates or imports new image attachments.
func legacyImageContent() throws -> NSAttributedString {
    let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
        NSColor.gray.setFill(); rect.fill(); return true
    }
    let data = try XCTUnwrap(image.tiffRepresentation)
    let attachment = NSTextAttachment(fileWrapper: FileWrapper(regularFileWithContents: data))
    attachment.fileWrapper?.preferredFilename = "legacy.tiff"
    attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
    return NSAttributedString(attachment: attachment)
}
