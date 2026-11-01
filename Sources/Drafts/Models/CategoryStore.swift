import Foundation
import Combine

struct NoteCategory: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var description: String
}

struct CategoryLabels: Codable, Equatable {
    var automatic = Set<UUID>()
    var included = Set<UUID>()
    var excluded = Set<UUID>()
    var effective: Set<UUID> { automatic.union(included).subtracting(excluded) }
}

final class CategoryStore: ObservableObject {
    private struct Document: Codable {
        var categories: [NoteCategory] = []
        var labels: [UUID: CategoryLabels] = [:]
        var topicPolicyVersion: Int?
    }
    @Published private var document = Document()
    @Published var lastError: String?
    let manualChanges = PassthroughSubject<UUID, Never>()
    private let url: URL
    private var readable = true
    var categories: [NoteCategory] { document.categories }
    var hasFixedTopics: Bool { document.topicPolicyVersion != nil }
    var organisationTopics: [NoteCategory] {
        guard hasFixedTopics else { return categories }
        return categories.filter { category in TopicPolicy.definitions.contains { $0.name == category.name } }
    }

    @discardableResult
    func configureFixedTopics() -> Bool {
        guard readable else { return false }
        guard document.topicPolicyVersion != TopicPolicy.version else { return true }
        var next = document
        for definition in TopicPolicy.definitions {
            if let index = next.categories.firstIndex(where: { $0.name.caseInsensitiveCompare(definition.name) == .orderedSame }) {
                next.categories[index].name = definition.name
                next.categories[index].description = definition.description
            } else {
                next.categories.append(NoteCategory(name: definition.name, description: definition.description))
            }
        }
        next.topicPolicyVersion = TopicPolicy.version
        return commit(next)
    }

    init(directory: URL) {
        url = directory.appendingPathComponent("categories.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: url.path) { document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)) }
        } catch {
            readable = false
            lastError = "Couldn’t read categories. The original file has been left untouched."
        }
    }

    func labels(for noteID: UUID) -> CategoryLabels { document.labels[noteID] ?? CategoryLabels() }
    func names(for noteID: UUID) -> String {
        let ids = labels(for: noteID).effective
        return categories.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
    }

    @discardableResult
    func saveCategory(id: UUID? = nil, name: String, description: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasFixedTopics, !categories.contains(where: { $0.id == id && $0.name == name }) {
            lastError = "The five topic names are fixed. You can edit their descriptions."
            return false
        }
        guard !name.isEmpty, name.lowercased() != "lookup", !name.contains("/"), !name.contains("\"") else {
            lastError = "Use a category name without / or quotes. Lookup is reserved for smart search."
            return false
        }
        guard name.utf8.count <= 160, description.utf8.count <= 1400 else {
            lastError = "Keep category names under 160 bytes and descriptions under 1400 bytes."
            return false
        }
        guard !categories.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            lastError = "A category with that name already exists."
            return false
        }
        var next = document
        if let id, let index = next.categories.firstIndex(where: { $0.id == id }) {
            next.categories[index].name = name
            next.categories[index].description = description
        } else { next.categories.append(NoteCategory(name: name, description: description)) }
        return commit(next)
    }

    func deleteCategory(_ id: UUID) {
        guard !hasFixedTopics else { lastError = "The five fixed topics cannot be deleted."; return }
        var next = document
        next.categories.removeAll { $0.id == id }
        for key in Array(next.labels.keys) {
            next.labels[key]?.automatic.remove(id)
            next.labels[key]?.included.remove(id)
            next.labels[key]?.excluded.remove(id)
        }
        _ = commit(next)
    }

    @discardableResult
    func setManual(_ categoryID: UUID, noteID: UUID, included: Bool) -> Bool {
        var next = document
        var labels = labels(for: noteID)
        if included { labels.included.insert(categoryID); labels.excluded.remove(categoryID) }
        else { labels.excluded.insert(categoryID); labels.included.remove(categoryID) }
        if included, hasFixedTopics, let topic = categories.first(where: { $0.id == categoryID }), TopicPolicy.domains.contains(topic.name),
           let fallback = categories.first(where: { $0.name == "Scratchpad" })?.id {
            labels.automatic.remove(fallback)
        }
        next.labels[noteID] = labels
        guard commit(next) else { return false }
        manualChanges.send(noteID)
        return true
    }

    func useAutomatic(noteID: UUID) {
        var next = document
        var labels = labels(for: noteID)
        labels.included = []; labels.excluded = []
        next.labels[noteID] = labels
        if commit(next) { manualChanges.send(noteID) }
    }

    @discardableResult
    func restoreManualLabels(_ labels: CategoryLabels, noteID: UUID) -> Bool {
        var next = document
        var current = self.labels(for: noteID)
        current.included = labels.included; current.excluded = labels.excluded
        if hasFixedTopics, let fallback = categories.first(where: { $0.name == "Scratchpad" })?.id {
            let domains = Set(categories.filter { TopicPolicy.domains.contains($0.name) }.map(\.id))
            if !current.effective.isDisjoint(with: domains) { current.automatic.remove(fallback) }
            else if labels.automatic.contains(fallback) { current.automatic.insert(fallback) }
        }
        next.labels[noteID] = current
        guard commit(next) else { return false }
        manualChanges.send(noteID)
        return true
    }

    func confirmTopics(noteID: UUID) {
        var next = document
        var labels = labels(for: noteID)
        labels.included = labels.effective
        labels.excluded = Set(organisationTopics.map(\.id)).subtracting(labels.included)
        next.labels[noteID] = labels
        if commit(next) { manualChanges.send(noteID) }
    }

    @discardableResult
    func setAutomatic(_ ids: Set<UUID>, noteID: UUID) -> Bool {
        var next = document
        var labels = labels(for: noteID)
        labels.automatic = ids.intersection(Set(categories.map(\.id)))
        next.labels[noteID] = labels
        return next.labels != document.labels ? commit(next) : true
    }

    @discardableResult
    func applyTopics(_ analysis: TopicAnalysis, noteID: UUID, useFallback: Bool = true) throws -> Bool {
        let analysis = try analysis.validated(allowedTopics: organisationTopics)
        var next = document
        var ids = Set<UUID>()
        for name in analysis.topics {
            if let topic = next.categories.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                ids.insert(topic.id)
            } else { throw TopicModelError.invalidOutput }
        }
        var labels = labels(for: noteID)
        labels.automatic = ids // Manual inclusions/exclusions remain authoritative.
        if hasFixedTopics, let fallback = categories.first(where: { $0.name == "Scratchpad" })?.id {
            let domainIDs = Set(categories.filter { TopicPolicy.domains.contains($0.name) }.map(\.id))
            if !labels.effective.isDisjoint(with: domainIDs) || !useFallback {
                labels.automatic.remove(fallback)
            } else { labels.automatic.insert(fallback) }
        }
        next.labels[noteID] = labels
        return commit(next)
    }

    func prune(survivingIDs: Set<UUID>) {
        var next = document
        next.labels = next.labels.filter { survivingIDs.contains($0.key) }
        if next.labels != document.labels { _ = commit(next) }
    }

    private func commit(_ next: Document) -> Bool {
        guard readable else { return false }
        do {
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next
            lastError = nil
            return true
        } catch { lastError = "Couldn’t save categories: \(error.localizedDescription)"; return false }
    }
}
