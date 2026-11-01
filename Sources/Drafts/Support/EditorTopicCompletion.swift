import Foundation

struct EditorTopicCompletion {
    let range: NSRange
    let query: String
    let topics: [NoteCategory]

    static func find(in text: String, selection: NSRange, topics: [NoteCategory]) -> Self? {
        let source = text as NSString
        guard selection.length == 0, selection.location <= source.length else { return nil }
        let prefix = source.substring(to: selection.location)
        let token = prefix.components(separatedBy: .whitespacesAndNewlines).last ?? ""
        guard token.hasPrefix("/"), !token.hasPrefix("//") else { return nil }
        let query = String(token.dropFirst())
        guard query.count <= 64, query.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return nil }
        if selection.location < source.length {
            let next = source.substring(with: NSRange(location: selection.location, length: 1))
            guard next.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { return nil }
        }
        let matches = topics.filter { query.isEmpty || $0.name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }
        guard !matches.isEmpty else { return nil }
        return Self(range: NSRange(location: selection.location - token.utf16.count, length: token.utf16.count), query: query, topics: matches)
    }
}
