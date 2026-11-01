import Foundation
import Combine

struct TopicMemoryExample: Codable, Equatable, Sendable {
    var text: String
    var includedTopics: [String]
    var excludedTopics: [String]
}

struct TopicMemorySummary: Identifiable {
    var id: UUID
    var title: String
    var included: String
    var excluded: String
}

final class TopicMemoryBank: ObservableObject {
    private struct Record: Codable, Equatable {
        var fingerprint: String
        var included: Set<UUID>
        var excluded: Set<UUID>
    }
    private struct Document: Codable {
        var initialised = false
        var records: [UUID: Record] = [:]
    }
    @Published private var document = Document()
    @Published private(set) var lastError: String?
    private let url: URL
    private var readable = true
    var count: Int { document.records.count }
    var revision: String {
        TopicAnalysis.fingerprint(document.records.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            let record = document.records[id]!
            return "\(id)|\(record.fingerprint)|\(record.included.map(\.uuidString).sorted())|\(record.excluded.map(\.uuidString).sorted())"
        }.joined(separator: "\n"))
    }

    init(directory: URL) {
        url = directory.appendingPathComponent("topic-memory.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) { document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)) }
        } catch { readable = false; lastError = "Couldn’t read topic memory. The existing file was left untouched." }
    }

    func seedIfNeeded(notes: [Note], categories: CategoryStore) {
        guard !document.initialised else { return }
        var next = document; next.initialised = true
        for note in notes where note.deletedAt == nil && !note.isBlank {
            let labels = categories.labels(for: note.id)
            if !labels.included.isEmpty || !labels.excluded.isEmpty {
                next.records[note.id] = Record(fingerprint: TopicAnalysis.fingerprint(note.text), included: labels.included, excluded: labels.excluded)
            }
        }
        _ = commit(next)
    }

    func remember(_ note: Note, labels: CategoryLabels) {
        guard note.deletedAt == nil, !note.isBlank else { return }
        var next = document; next.initialised = true
        if labels.included.isEmpty && labels.excluded.isEmpty { next.records.removeValue(forKey: note.id) }
        else { next.records[note.id] = Record(fingerprint: TopicAnalysis.fingerprint(note.text), included: labels.included, excluded: labels.excluded) }
        _ = commit(next)
    }

    func prune(notes: [Note], allowedIDs: Set<UUID>) {
        let active = Dictionary(uniqueKeysWithValues: notes.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        var next = document
        next.records = next.records.filter { id, record in
            guard let note = active[id], TopicAnalysis.fingerprint(note.text) == record.fingerprint else { return false }
            return record.included.isSubset(of: allowedIDs) && record.excluded.isSubset(of: allowedIDs)
        }
        if next.records != document.records { _ = commit(next) }
    }

    func examples(for text: String, excluding id: UUID, notes: [Note], categories: [NoteCategory], pendingIDs: Set<UUID> = []) -> [TopicMemoryExample] {
        let words = Self.words(text)
        guard !words.isEmpty else { return [] }
        let allowed = Set(categories.map(\.id))
        let active = Dictionary(uniqueKeysWithValues: notes.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        let candidates = document.records.compactMap { key, record -> (UUID, Double, TopicMemoryExample)? in
            guard key != id, !pendingIDs.contains(key), let note = active[key],
                  TopicAnalysis.fingerprint(note.text) == record.fingerprint,
                  record.included.isSubset(of: allowed), record.excluded.isSubset(of: allowed) else { return nil }
            let otherWords = Self.words(note.text), shared = words.intersection(otherWords).count
            guard shared >= 2 else { return nil }
            let score = Double(shared) / sqrt(Double(max(1, words.count * otherWords.count)))
            let example = TopicMemoryExample(text: String(note.text.prefix(800)),
                                             includedTopics: categories.filter { record.included.contains($0.id) }.map(\.name),
                                             excludedTopics: categories.filter { record.excluded.contains($0.id) }.map(\.name))
            return (key, score, example)
        }
        return candidates.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }.prefix(3).map(\.2)
    }

    func summaries(notes: [Note], categories: [NoteCategory]) -> [TopicMemorySummary] {
        notes.filter { $0.deletedAt == nil && document.records[$0.id] != nil }.map { note in
            let record = document.records[note.id]!
            return TopicMemorySummary(id: note.id, title: note.title,
                                      included: categories.filter { record.included.contains($0.id) }.map(\.name).joined(separator: ", "),
                                      excluded: categories.filter { record.excluded.contains($0.id) }.map(\.name).joined(separator: ", "))
        }
    }

    func forget(_ id: UUID) { var next = document; next.records.removeValue(forKey: id); _ = commit(next) }
    func clear() { _ = commit(Document(initialised: true, records: [:])) }

    private static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["the", "and", "for", "with", "this", "that", "from", "have", "what", "please", "would", "could", "should", "into", "about"]
        return Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 && !stop.contains($0) })
    }

    private func commit(_ next: Document) -> Bool {
        guard readable else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next; lastError = nil; return true
        } catch { lastError = "Couldn’t save topic memory: \(error.localizedDescription)"; return false }
    }
}
