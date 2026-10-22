import AppKit

// Used only for an explicit paste or drop. Drafts never reads or monitors the clipboard on open.
enum PasteContent {
    static func read(from pasteboard: NSPasteboard) -> NSAttributedString? {
        for (type, documentType) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf)] {
            if let data = pasteboard.data(forType: type),
               let value = try? NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil) {
                let basic = EditorStyle.basicFormatting(value)
                if value.string.contains("\u{fffc}"), basic.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                if basic.length > 0 { return basic }
            }
        }
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return nil }
        return EditorStyle.plain(string)
    }
}
