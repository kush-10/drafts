import AppKit

struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var text: String
    var richText: Data

    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    var title: String {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return line.isEmpty ? "Untitled note" : String(line.prefix(100))
    }

    var preview: String {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String(lines.dropFirst().joined(separator: " ").prefix(180))
    }

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func attributedString() throws -> NSAttributedString {
        try NSAttributedString(data: richText, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
    }

    static func encode(_ content: NSAttributedString) throws -> Data {
        try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }

    static func make(content: NSAttributedString, now: Date = Date()) throws -> Note {
        Note(id: UUID(), createdAt: now, updatedAt: now, text: searchableText(content), richText: try encode(content))
    }

    static func searchableText(_ content: NSAttributedString) -> String {
        content.string.replacingOccurrences(of: "\u{fffc}", with: " [Image] ")
    }
}

enum EditorStyle {
    static let font = NSFont.systemFont(ofSize: 16)
    static let textColor = NSColor(white: 0.88, alpha: 1)
    static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 6
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    static func plain(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes)
    }

    static func adaptingToAppearance(_ content: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: content)
        result.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func basicFormatting(_ content: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length)) { source, range, _ in
            // Remove new image attachments, links, heading sizes, code styling, colors and tables.
            let text = (content.string as NSString).substring(with: range).replacingOccurrences(of: "\u{fffc}", with: "")
            guard !text.isEmpty else { return }
            var kept = attributes
            if let sourceFont = source[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: sourceFont).intersection([.boldFontMask, .italicFontMask])
                if !traits.isEmpty { kept[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            }
            if let underline = source[.underlineStyle] as? Int, underline != 0 { kept[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: text, attributes: kept))
        }
        return result
    }
}
