import Foundation
import Combine

final class IntelligenceController: ObservableObject {
    let categories: CategoryStore // Existing IDs/files are retained; the UI now calls these topics.
    let models: TopicModelManager
    let organisationState: OrganisationState
    let memory: TopicMemoryBank
    private let store: NoteStore
    private let preferences: PreferencesStore
    private let runtime: any TopicOrganiser
    private let saveDelay: Duration
    private let typingQuietSeconds: TimeInterval
    @Published private(set) var status = "Topics run locally after saves"
    @Published private(set) var isOrganising = false
    @Published private(set) var isOrganisingAll = false
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchCompleted = 0
    @Published private(set) var batchFailed = 0
    private var batchRemaining = Set<UUID>()
    @Published var lastError: String?
    private var organisation: Task<Void, Never>?
    private var debounces: [UUID: Task<Void, Never>] = [:]
    private var queue: [UUID] = []
    private var processingID: UUID?
    private var editGeneration = 0
    private var stopGeneration = 0
    private var pendingMemoryConfirmations = Set<UUID>()
    private var lastEdit = Date.distantPast
    private var subscriptions = Set<AnyCancellable>()

    init(store: NoteStore, preferences: PreferencesStore, models: TopicModelManager? = nil, saveDelay: Duration = .seconds(3), typingQuietSeconds: TimeInterval = 1) {
        self.store = store; self.preferences = preferences; self.saveDelay = saveDelay
        self.typingQuietSeconds = typingQuietSeconds
        let models = models ?? TopicModelManager()
        self.models = models; runtime = models.runtime
        let directory = store.directory.appendingPathComponent(".drafts", isDirectory: true)
        categories = CategoryStore(directory: directory)
        organisationState = OrganisationState(directory: directory)
        memory = TopicMemoryBank(directory: directory)
        if !categories.configureFixedTopics() { lastError = categories.lastError }
        if preferences.value.useTopicMemory { memory.seedIfNeeded(notes: store.activeNotes.filter { !store.hasPendingChanges($0.id) }, categories: categories) }
        store.didSaveContent.sink { [weak self] note in self?.saved(note) }.store(in: &subscriptions)
        categories.manualChanges.sink { [weak self] id in
            self?.rememberManualTopics(id)
        }.store(in: &subscriptions)
        store.willEditContent.sink { [weak self] _ in
            guard let self else { return }
            self.editGeneration += 1; self.lastEdit = Date()
            // Stop GPU work as soon as typing resumes, even if another saved note was running.
            if self.processingID != nil { self.organisation?.cancel(); self.runtime.cancel() }
        }.store(in: &subscriptions)
        store.$notes.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            let ids = Set(self.store.notes.map(\.id))
            self.categories.prune(survivingIDs: ids); self.organisationState.prune(ids: ids)
            self.memory.prune(notes: self.store.activeNotes, allowedIDs: Set(self.categories.organisationTopics.map(\.id)))
            if let id = self.processingID, self.store.note(id)?.deletedAt != nil || !ids.contains(id) {
                self.organisation?.cancel(); self.runtime.cancel()
            }
        }.store(in: &subscriptions)
        preferences.$value.dropFirst().sink { [weak self] value in
            guard let self else { return }
            if value.useTopicMemory { self.memory.seedIfNeeded(notes: self.store.activeNotes.filter { !self.store.hasPendingChanges($0.id) }, categories: self.categories) }
            if (!value.autoOrganise && value.autoOrganise != self.preferences.value.autoOrganise) || value.topicModelID != self.preferences.value.topicModelID || value.useTopicMemory != self.preferences.value.useTopicMemory {
                self.stop()
            } else if value.modelIdleSeconds != self.preferences.value.modelIdleSeconds, !self.isOrganising {
                self.runtime.scheduleUnload(after: value.modelIdleSeconds)
            }
        }.store(in: &subscriptions)
        models.onModelRemoved = { [weak self] _ in self?.stop() }
    }

    deinit { organisation?.cancel(); debounces.values.forEach { $0.cancel() }; runtime.unload() }

    private var context: String {
        let definitions = categories.organisationTopics.map { "\($0.id)|\($0.name)|\($0.description)" }.joined(separator: "\n")
        return "\(TopicAnalysis.promptVersion)|\(preferences.value.topicModelID)|\(TopicAnalysis.fingerprint(definitions))|\(preferences.value.useTopicMemory ? memory.revision : "memory-off")"
    }

    var memorySummaries: [TopicMemorySummary] { memory.summaries(notes: store.activeNotes, categories: categories.organisationTopics) }

    func rememberManualTopics(_ id: UUID) {
        guard preferences.value.useTopicMemory, let note = store.note(id) else { return }
        if store.hasPendingChanges(id) { pendingMemoryConfirmations.insert(id) }
        else { memory.remember(note, labels: categories.labels(for: id)) }
    }

    var organisableNoteCount: Int { store.activeNotes.filter { !$0.isBlank }.count }
    var hasSelectedModel: Bool {
        models.installedDirectory(for: preferences.value.topicModelID) != nil &&
        TopicModel.catalogue.first(where: { $0.id == preferences.value.topicModelID })?.canRun() == true
    }

    func organiseAllNotes() {
        guard !isOrganisingAll else { return }
        guard hasSelectedModel else { lastError = "Download and select a local model in Settings → Models first."; return }
        guard store.flush() else { lastError = store.lastError; return }
        let ids = store.activeNotes.filter { !$0.isBlank }.map(\.id)
        guard !ids.isEmpty else { status = "No saved notes to organise"; return }
        batchRemaining = Set(ids); batchTotal = ids.count; batchCompleted = 0; batchFailed = 0
        isOrganisingAll = true; lastError = nil
        for id in ids {
            debounces.removeValue(forKey: id)?.cancel()
            if id != processingID, !queue.contains(id) { queue.append(id) }
        }
        status = "Organising all notes…"
        startQueue()
    }

    func cancelOrganisation() {
        stop()
        status = "Organisation cancelled · completed topic assignments were kept"
    }

    private func finishBatchNote(_ id: UUID, failed: Bool = false) {
        guard batchRemaining.remove(id) != nil else { return }
        batchCompleted += 1
        if failed { batchFailed += 1 }
        if batchRemaining.isEmpty {
            isOrganisingAll = false
            status = batchFailed == 0 ? "Organised all \(batchTotal) notes" : "Processed \(batchTotal) notes · \(batchFailed) need attention"
        }
    }

    private func saved(_ note: Note) {
        if pendingMemoryConfirmations.remove(note.id) != nil, preferences.value.useTopicMemory { memory.remember(note, labels: categories.labels(for: note.id)) }
        debounces.removeValue(forKey: note.id)?.cancel()
        guard preferences.value.autoOrganise, note.deletedAt == nil else { return }
        let fingerprint = TopicAnalysis.fingerprint(note.text)
        if let record = organisationState.records[note.id], record.phase == .completed,
           record.contentFingerprint == fingerprint, record.contextFingerprint == context { return }
        guard organisationState.record(.init(phase: .pending, contentFingerprint: fingerprint, contextFingerprint: context), for: note.id) else {
            lastError = organisationState.lastError; return
        }
        debounces[note.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: saveDelay) } catch { return }
            debounces.removeValue(forKey: note.id)
            guard let current = store.note(note.id), current.deletedAt == nil,
                  !store.hasPendingChanges(note.id), TopicAnalysis.fingerprint(current.text) == fingerprint else { return }
            if !queue.contains(note.id) { queue.append(note.id) }
            startQueue()
        }
    }

    private func startQueue() {
        guard organisation == nil, preferences.value.autoOrganise || isOrganisingAll, !queue.isEmpty else { return }
        organisation = Task { @MainActor [weak self] in await self?.drainQueue() }
    }

    @MainActor private func drainQueue() async {
        isOrganising = true
        defer {
            organisation = nil; processingID = nil; isOrganising = false
            runtime.scheduleUnload(after: preferences.value.modelIdleSeconds)
            if !queue.isEmpty { startQueue() }
        }
        while !queue.isEmpty, preferences.value.autoOrganise || isOrganisingAll, !Task.isCancelled {
            // Typing is always higher priority. Do not start/loading another model mid-edit.
            if store.pendingCount > 0 || Date().timeIntervalSince(lastEdit) < typingQuietSeconds {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                continue
            }
            let id = queue.removeFirst()
            guard let note = store.note(id), note.deletedAt == nil, !store.hasPendingChanges(id) else { finishBatchNote(id); continue }
            let fingerprint = TopicAnalysis.fingerprint(note.text), configuration = context, generation = editGeneration, stopToken = stopGeneration
            let definitions = categories.organisationTopics
            processingID = id
            defer {
                processingID = nil
                if preferences.value.modelIdleSeconds == 0 { runtime.unload() }
                if var record = organisationState.records[id], record.phase == .running {
                    record.phase = .pending; record.updatedAt = Date()
                    _ = organisationState.record(record, for: id)
                }
            }
            do {
                let analysis: TopicAnalysis
                if note.isBlank { analysis = TopicAnalysis(topics: []) }
                else {
                    guard let directory = models.installedDirectory(for: preferences.value.topicModelID) else { throw TopicModelError.notInstalled }
                    guard TopicModel.catalogue.first(where: { $0.id == preferences.value.topicModelID })?.canRun() == true else { throw TopicModelError.unavailable }
                    guard organisationState.record(.init(phase: .running, contentFingerprint: fingerprint, contextFingerprint: configuration), for: id) else {
                        throw TopicModelError.failed(organisationState.lastError ?? "Couldn’t save organisation status.")
                    }
                    status = "Organising saved note…"
                    let examples = preferences.value.useTopicMemory ? memory.examples(for: note.text, excluding: id, notes: store.activeNotes, categories: definitions,
                                                                                    pendingIDs: Set(store.activeNotes.filter { store.hasPendingChanges($0.id) }.map(\.id))) : []
                    analysis = try await runtime.analyse(text: note.text, topics: definitions, memory: examples, modelDirectory: directory)
                }
                try Task.checkCancellation()
                guard let current = store.note(id), current.deletedAt == nil, !store.hasPendingChanges(id),
                      current.text == note.text, generation == editGeneration, context == configuration,
                       definitions == categories.organisationTopics else {
                    if batchRemaining.contains(id), store.note(id)?.deletedAt == nil, store.note(id) != nil { queue.append(id) }
                    else { finishBatchNote(id) }
                    continue
                }
                guard try categories.applyTopics(analysis, noteID: id, useFallback: !note.isBlank) else { throw TopicModelError.failed(categories.lastError ?? "Couldn’t save topics.") }
                guard organisationState.record(.init(phase: .completed, contentFingerprint: fingerprint, contextFingerprint: configuration), for: id) else {
                    throw TopicModelError.failed(organisationState.lastError ?? "Couldn’t save organisation status.")
                }
                status = "Topics up to date"; lastError = nil
                finishBatchNote(id)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    // Interrupted saved snapshots are retried when typing settles; edited notes wait for their next successful save.
                    if let current = store.note(id), current.deletedAt == nil, current.text == note.text,
                        !store.hasPendingChanges(id), !queue.contains(id), preferences.value.autoOrganise || batchRemaining.contains(id),
                        stopToken == stopGeneration { queue.insert(id, at: 0) }
                    else if batchRemaining.contains(id), stopToken == stopGeneration { queue.append(id) }
                    return
                }
                guard store.note(id)?.text == note.text, context == configuration else {
                    if batchRemaining.contains(id), store.note(id)?.deletedAt == nil, store.note(id) != nil { queue.append(id) }
                    else { finishBatchNote(id) }
                    continue
                }
                lastError = error.localizedDescription; status = "Topics need attention · notes are saved"
                _ = organisationState.record(.init(phase: .failed, contentFingerprint: fingerprint, contextFingerprint: configuration, error: error.localizedDescription), for: id)
                finishBatchNote(id, failed: true)
            }
        }
    }

    private func stop() {
        stopGeneration += 1
        organisation?.cancel(); queue.removeAll()
        batchRemaining.removeAll(); isOrganisingAll = false
        debounces.values.forEach { $0.cancel() }; debounces.removeAll()
        runtime.unload()
        status = "Topics run locally after saves"
    }

    func shutdown() { stop(); models.cancelDownload() }
}
