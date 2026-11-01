import Foundation

struct SmartQuery: Equatable {
    var text = ""
    var categoryNames: [String] = []

    init(_ input: String, categories: [NoteCategory] = []) {
        let names = categories.map(\.name).sorted { $0.count > $1.count }
        var remaining = input[...]
        var words: [String] = []
        while !remaining.isEmpty {
            remaining = remaining.drop(while: \.isWhitespace)
            guard !remaining.isEmpty else { break }
            if remaining.first == "/" {
                remaining = remaining.dropFirst()
                // Continue accepting old saved queries, but completion never inserts quotes.
                if remaining.first == "\"", let end = remaining.dropFirst().firstIndex(of: "\"") {
                    categoryNames.append(String(remaining[remaining.index(after: remaining.startIndex)..<end]))
                    remaining = remaining[remaining.index(after: end)...]
                    continue
                }
                // Match the longest existing name so categories containing spaces need no quotes.
                if let match = names.compactMap({ name -> Range<String.Index>? in
                    guard let range = remaining.range(of: name, options: [.anchored, .caseInsensitive, .diacriticInsensitive]),
                          range.upperBound == remaining.endIndex || remaining[range.upperBound].isWhitespace else { return nil }
                    return range
                }).first {
                    categoryNames.append(String(remaining[match]))
                    remaining = remaining[match.upperBound...]
                    continue
                }
                let end = remaining.firstIndex(where: \.isWhitespace) ?? remaining.endIndex
                let value = String(remaining[..<end])
                categoryNames.append(value)
                remaining = remaining[end...]
            } else {
                let end = remaining.firstIndex(where: \.isWhitespace) ?? remaining.endIndex
                words.append(String(remaining[..<end]))
                remaining = remaining[end...]
            }
        }
        text = words.joined(separator: " ")
    }

    static func completing(_ input: String, with name: String) -> String {
        guard let slash = input.range(of: "/", options: .backwards) else { return input }
        return String(input[..<slash.lowerBound]) + "/" + name + " "
    }

    func categoryIDs(in categories: [NoteCategory]) -> Set<UUID>? {
        var ids = Set<UUID>()
        for name in categoryNames {
            guard let category = categories.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
            ids.insert(category.id)
        }
        return ids
    }
}
