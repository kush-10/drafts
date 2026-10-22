import AppKit
import Combine

final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var lastError: String?
    @Published private(set) var pendingCount = 0
    let directory: URL
    private var pending = Set<UUID>()
    private var pendingContent: [UUID: NSAttributedString] = [:]
    private var saveTask: DispatchWorkItem?
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drafts/Notes", isDirectory: true)
        do {
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let urls = try fileManager.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "json" {
                do {
                    let note = try JSONDecoder().decode(Note.self, from: Data(contentsOf: url))
                    _ = try note.attributedString()
                    guard !notes.contains(where: { $0.id == note.id }) else { continue }
                    notes.append(note)
                } catch {
                    lastError = "Couldn’t read \(url.lastPathComponent). Its file has been left untouched. \(error.localizedDescription)"
                }
            }
            sort()
        } catch { report(error) }
    }

    var activeNotes: [Note] { notes.filter { $0.deletedAt == nil } }
    var notesByCreation: [Note] {
        activeNotes.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
    var newestNote: Note? { notesByCreation.first }
    var trashedNotes: [Note] { notes.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    func note(_ id: UUID?) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func create(content: NSAttributedString = EditorStyle.plain(""), now: Date = Date()) -> Note? {
        do {
            let note = try Note.make(content: content, now: now)
            // Persist before opening so even a newly created, empty note exists on disk.
            try write(note)
            notes.insert(note, at: 0)
            return note
        } catch { report(error); return nil }
    }

    @discardableResult
    func newDraft(preferredID: UUID? = nil) -> Note? {
        guard flush() else { return nil }
        if let current = note(preferredID), current.deletedAt == nil, current.isBlank { return current }
        if let blank = notesByCreation.first(where: \.isBlank) { return blank }
        return create()
    }

    func update(_ id: UUID, content: NSAttributedString, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        // Keep an immutable in-memory copy; serialize attachments only when the debounce fires.
        // A failed encode or write remains pending rather than silently losing the edit.
        pendingContent[id] = NSAttributedString(attributedString: content)
        notes[index].text = Note.searchableText(content)
        notes[index].updatedAt = now
        sort()
        markPending(id)
    }

    func trash(_ id: UUID, now: Date = Date()) {
        mutate(id) { $0.deletedAt = now }
    }

    func restore(_ id: UUID, now: Date = Date()) {
        mutate(id) { $0.deletedAt = nil; $0.updatedAt = now }
        sort()
    }

    func deletePermanently(_ id: UUID) {
        guard let note = note(id), note.deletedAt != nil else { return }
        removeFileAndRecord(id)
    }

    private func removeFileAndRecord(_ id: UUID) {
        do {
            let url = fileURL(id)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            pending.remove(id)
            pendingContent.removeValue(forKey: id)
            pendingCount = pending.count
            notes.removeAll { $0.id == id }
        } catch { report(error) }
    }

    func cleanup(preferences: Preferences, excluding: UUID? = nil, now: Date = Date()) {
        guard preferences.autoDeleteEnabled, flush() else { return }
        let cutoff = now.addingTimeInterval(-preferences.retentionInterval)
        let expired = notes.filter { $0.id != excluding && $0.updatedAt <= cutoff }
        for note in expired { removeFileAndRecord(note.id) }
    }

    @discardableResult
    func flush() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        for id in Array(pending) {
            guard var note = note(id) else { pending.remove(id); pendingContent.removeValue(forKey: id); continue }
            do {
                if let content = pendingContent[id] { note.richText = try Note.encode(content) }
                try write(note)
                if let index = notes.firstIndex(where: { $0.id == id }) { notes[index] = note }
                pending.remove(id)
                pendingContent.removeValue(forKey: id)
            }
            catch { report(error) }
        }
        pendingCount = pending.count
        return pending.isEmpty
    }

    private func mutate(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[index])
        markPending(id)
        flush()
    }

    private func markPending(_ id: UUID) {
        pending.insert(id)
        pendingCount = pending.count
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.flush() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func sort() { notes.sort { $0.updatedAt > $1.updatedAt } }
    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func write(_ note: Note) throws { try JSONEncoder().encode(note).write(to: fileURL(note.id), options: .atomic) }
    private func report(_ error: Error) { lastError = "Drafts couldn’t save or read a note: \(error.localizedDescription)" }
}
