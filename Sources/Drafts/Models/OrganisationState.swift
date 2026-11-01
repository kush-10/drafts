import Foundation
import Combine

enum OrganisationPhase: String, Codable { case pending, running, completed, failed }

struct OrganisationRecord: Codable {
    var phase: OrganisationPhase
    var contentFingerprint: String
    var contextFingerprint: String
    var error: String?
    var updatedAt = Date()
}

final class OrganisationState: ObservableObject {
    private struct Document: Codable { var records: [UUID: OrganisationRecord] = [:] }
    @Published private var document = Document()
    @Published private(set) var lastError: String?
    private let url: URL
    private var readable = true
    var records: [UUID: OrganisationRecord] { document.records }

    init(directory: URL) {
        url = directory.appendingPathComponent("organisation.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) { document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)) }
            for id in document.records.keys where document.records[id]?.phase == .running { document.records[id]?.phase = .pending }
        } catch { readable = false; lastError = "Couldn’t read organisation state. The original file was left untouched." }
    }

    @discardableResult
    func record(_ record: OrganisationRecord, for id: UUID) -> Bool {
        var next = document; next.records[id] = record
        return commit(next)
    }

    func prune(ids: Set<UUID>) {
        var next = document; next.records = next.records.filter { ids.contains($0.key) }
        if next.records.count != document.records.count { _ = commit(next) }
    }

    private func commit(_ next: Document) -> Bool {
        guard readable else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next; lastError = nil; return true
        } catch { lastError = "Couldn’t save organisation state: \(error.localizedDescription)"; return false }
    }
}
