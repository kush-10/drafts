import AppKit
import Combine
import XCTest
@testable import Drafts

private final class ProbeTopics: TopicOrganiser, @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private var memories: [[TopicMemoryExample]] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    var gated = false
    var result = TopicAnalysis(topics: ["Dev"])
    private(set) var cancellations = 0
    private(set) var unloadSeconds: Int?
    var inputs: [String] { lock.withLock { texts } }
    var examples: [[TopicMemoryExample]] { lock.withLock { memories } }
    var waiting: Bool { lock.withLock { !pending.isEmpty } }
    func analyse(text: String, topics: [NoteCategory], memory: [TopicMemoryExample], modelDirectory: URL) async throws -> TopicAnalysis {
        lock.withLock { texts.append(text); memories.append(memory) }
        if gated { await withCheckedContinuation { continuation in lock.withLock { pending.append(continuation) } } }
        return result
    }
    func release() { let continuations = lock.withLock { let values = pending; pending = []; gated = false; return values }; continuations.forEach { $0.resume() } }
    func cancel() { lock.withLock { cancellations += 1 } }
    func unload() { cancel() }
    func scheduleUnload(after seconds: Int) { lock.withLock { unloadSeconds = seconds } }
}

final class IntelligenceTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftsTopicsTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "DraftsTopicsTests.\(UUID())"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    private func fixture(probe: ProbeTopics = ProbeTopics()) throws -> (NoteStore, PreferencesStore, IntelligenceController, ProbeTopics) {
        let notes = NoteStore(directory: directory.appendingPathComponent("Notes"))
        let prefs = PreferencesStore(defaults: defaults)
        prefs.value.topicModelID = "qwen3.5-4b"
        let models = TopicModelManager(directory: directory.appendingPathComponent("Models"), runtime: probe)
        // Sparse fixture weights: tests never download or load a real model.
        let model = TopicModel.catalogue[0]
        let root = models.directory.appendingPathComponent(model.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer.json"))
        let weights = root.appendingPathComponent("model.safetensors")
        FileManager.default.createFile(atPath: weights.path, contents: nil)
        let handle = try FileHandle(forWritingTo: weights)
        try handle.truncate(atOffset: UInt64(model.downloadBytes - 4)); try handle.close()
        let files = [ModelFile(path: "config.json", size: 2), ModelFile(path: "tokenizer.json", size: 2), ModelFile(path: "model.safetensors", size: model.downloadBytes - 4)]
        let modelJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model))
        let filesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
        try JSONSerialization.data(withJSONObject: ["model": modelJSON, "files": filesJSON]).write(to: root.appendingPathComponent("installed.json"))
        models.refreshInstalled()
        XCTAssertEqual(models.installedIDs, [model.id])
        let controller = IntelligenceController(store: notes, preferences: prefs, models: models, saveDelay: .milliseconds(25), typingQuietSeconds: 0)
        return (notes, prefs, controller, probe)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out waiting for topic processing")
    }

    func testTopicQueriesAcceptMultiwordNamesAndNoLongerRunLookup() {
        let topics = [NoteCategory(name: "Work", description: ""), NoteCategory(name: "Personal projects", description: "")]
        let query = SmartQuery("/Personal projects design", categories: topics)
        XCTAssertEqual(query.categoryNames, ["Personal projects"])
        XCTAssertEqual(query.text, "design")
        XCTAssertEqual(query.categoryIDs(in: topics), [topics[1].id])
        XCTAssertNil(SmartQuery("/lookup ideas").categoryIDs(in: topics))
        XCTAssertEqual(SmartQuery.completing("/Pers", with: "Personal projects"), "/Personal projects ")
    }

    func testTopicsAreValidatedBeforeAnyAssignmentsChange() throws {
        let topics = CategoryStore(directory: directory)
        topics.saveCategory(name: "Work", description: "")
        topics.saveCategory(name: "Personal", description: "")
        let id = UUID(), work = topics.categories[0].id
        topics.setManual(work, noteID: id, included: false)
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["work", "Personal"]), noteID: id))
        XCTAssertEqual(topics.names(for: id), "Personal")
        XCTAssertEqual(topics.categories.count, 2)
        XCTAssertThrowsError(try topics.applyTopics(.init(topics: ["Bad/topic"]), noteID: id))
        XCTAssertThrowsError(try topics.applyTopics(.init(topics: ["Invented"]), noteID: id))
        XCTAssertEqual(topics.categories.count, 2)
        XCTAssertEqual(CategoryStore(directory: directory).names(for: id), "Personal")
    }

    func testManualCategoriesPersistAndOverrideAutomaticAssignments() throws {
        let topics = CategoryStore(directory: directory)
        topics.saveCategory(name: "Work", description: "Business ideas")
        topics.saveCategory(name: "Recipes", description: "Food")
        let work = topics.categories[0].id, recipes = topics.categories[1].id, note = UUID()
        topics.setAutomatic([work, recipes], noteID: note)
        topics.setManual(work, noteID: note, included: false)
        topics.setManual(recipes, noteID: note, included: true)
        topics.setAutomatic([work], noteID: note)
        XCTAssertEqual(CategoryStore(directory: directory).labels(for: note).effective, [recipes])
        topics.useAutomatic(noteID: note)
        XCTAssertEqual(topics.labels(for: note).effective, [work])
    }

    func testCategoryRenameAndDeletionKeepAssignmentsAndNotesSafe() {
        let topics = CategoryStore(directory: directory)
        topics.saveCategory(name: "Work", description: "Business")
        let category = topics.categories[0].id, note = UUID()
        topics.setManual(category, noteID: note, included: true)
        XCTAssertTrue(topics.saveCategory(id: category, name: "Projects", description: "Plans"))
        XCTAssertEqual(topics.names(for: note), "Projects")
        XCTAssertFalse(topics.saveCategory(name: "projects", description: "Duplicate"))
        topics.deleteCategory(category)
        XCTAssertTrue(topics.labels(for: note).effective.isEmpty)
    }

    func testUnreadableCategoryFileIsNotOverwritten() throws {
        let url = directory.appendingPathComponent("categories.json"), bad = Data("broken data".utf8)
        try bad.write(to: url)
        let topics = CategoryStore(directory: directory)
        XCTAssertFalse(topics.saveCategory(name: "Work", description: ""))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }

    func testLongUnicodeNotesDoNotLoseTheirEnding() {
        let text = String(repeating: "日記とアイデア🌲 ", count: 1800) + "unique ending"
        let passages = TopicAnalysis.passages(text)
        XCTAssertGreaterThan(passages.count, 1)
        XCTAssertTrue(passages.allSatisfy { $0.utf8.count <= 8000 })
        XCTAssertEqual(passages.joined(), text)
    }

    func testWindowMemoryExpiresAndSurvivesWorkspaceRecreation() {
        let workspace = WorkspaceState(defaults: defaults), now = Date()
        workspace.rememberWindow(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), expanded: false, restoreFrame: nil, now: now)
        let reloaded = WorkspaceState(defaults: defaults)
        XCTAssertEqual(reloaded.rememberedWindow(minutes: 30, now: now.addingTimeInterval(1799))?.width, 1000)
        XCTAssertNil(reloaded.rememberedWindow(minutes: 30, now: now.addingTimeInterval(1800)))
    }

    @MainActor func testSaveTriggersTopicsWithoutHidingAndDoesNotRewriteNote() async throws {
        let (notes, _, controller, probe) = try fixture()
        defer { controller.shutdown() }
        let note = try XCTUnwrap(notes.create())
        notes.update(note.id, content: EditorStyle.plain("A saved work idea")); XCTAssertTrue(notes.flush())
        let file = notes.directory.appendingPathComponent(note.id.uuidString + ".json")
        let saved = try Data(contentsOf: file)
        try await waitUntil { controller.organisationState.records[note.id]?.phase == .completed }
        XCTAssertEqual(probe.inputs, ["A saved work idea"])
        XCTAssertEqual(controller.categories.names(for: note.id), "Dev")
        XCTAssertEqual(try Data(contentsOf: file), saved)
        XCTAssertEqual(probe.unloadSeconds, 30)
    }

    @MainActor func testRapidSavesCoalesceAndFailedSavesNeverRunAI() async throws {
        let (notes, _, controller, probe) = try fixture()
        defer { controller.shutdown() }
        let note = try XCTUnwrap(notes.create()), file = notes.directory.appendingPathComponent(note.id.uuidString + ".json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        notes.update(note.id, content: EditorStyle.plain("Unsaved")); XCTAssertFalse(notes.flush())
        try await Task.sleep(for: .milliseconds(50)); XCTAssertTrue(probe.inputs.isEmpty)
        try FileManager.default.removeItem(at: file)
        for i in 1...3 {
            notes.update(note.id, content: EditorStyle.plain("Revision \(i)")); XCTAssertTrue(notes.flush())
            try await Task.sleep(for: .milliseconds(3))
        }
        try await waitUntil { controller.organisationState.records[note.id]?.phase == .completed }
        XCTAssertEqual(probe.inputs, ["Revision 3"])
    }

    @MainActor func testTypingCancelsAnalysisAndStaleResultsCannotAddTopics() async throws {
        let probe = ProbeTopics(); probe.gated = true
        let (notes, _, controller, _) = try fixture(probe: probe)
        defer { probe.release(); controller.shutdown() }
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Saved snapshot")))
        try await waitUntil { probe.waiting }
        notes.update(note.id, content: EditorStyle.plain("Unsaved edit"))
        probe.release()
        try await waitUntil { !controller.isOrganising }
        XCTAssertTrue(controller.categories.labels(for: note.id).automatic.isEmpty)
        XCTAssertEqual(controller.organisationState.records[note.id]?.phase, .pending)
        XCTAssertGreaterThan(probe.cancellations, 0)
    }

    @MainActor func testTurningOffOrganisationDoesNotRequeueACancelledJob() async throws {
        let probe = ProbeTopics(); probe.gated = true
        let (notes, prefs, controller, _) = try fixture(probe: probe)
        defer { probe.release(); controller.shutdown() }
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Saved snapshot")))
        try await waitUntil { probe.waiting }
        prefs.value.autoOrganise = false; probe.release()
        try await waitUntil { !controller.isOrganising }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(probe.inputs.count, 1)
        XCTAssertTrue(controller.categories.labels(for: note.id).automatic.isEmpty)
    }

    @MainActor func testMetadataChangesAndModelSelectionDoNotRunAI() async throws {
        let (notes, prefs, controller, probe) = try fixture()
        defer { controller.shutdown() }
        let note = try XCTUnwrap(notes.create())
        let topic = try XCTUnwrap(controller.categories.categories.first { $0.name == "Mandir" }).id
        controller.categories.setManual(topic, noteID: note.id, included: true)
        notes.trash(note.id); notes.restore(note.id)
        prefs.value.topicModelID = "qwen3.5-9b"
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(probe.inputs.isEmpty)
        XCTAssertEqual(controller.categories.names(for: note.id), "Mandir")
    }

    func testTextAndTopicSearchUseSavedMetadataWithoutAI() throws {
        let notes = NoteStore(directory: directory.appendingPathComponent("Notes")), topics = CategoryStore(directory: directory)
        let first = try XCTUnwrap(notes.create(content: EditorStyle.plain("A design idea")))
        _ = notes.create(content: EditorStyle.plain("A shopping idea"))
        topics.saveCategory(name: "University", description: "")
        topics.setManual(topics.categories[0].id, noteID: first.id, included: true)
        XCTAssertEqual(NotesFilter.rows(store: notes, categories: topics, query: "university design").map(\.id), [first.id])
        XCTAssertEqual(NotesFilter.rows(store: notes, categories: topics, query: "/University").map(\.id), [first.id])
        XCTAssertEqual(NotesFilter.rows(store: notes, categories: topics, query: "", topic: topics.categories[0].id).map(\.id), [first.id])
    }

    func testModelFileVerificationRejectsCorruptionAndUnsafePaths() async throws {
        let file = directory.appendingPathComponent("weights.safetensors"), data = Data("test weights".utf8)
        try data.write(to: file)
        let descriptor = ModelFile(path: "weights.safetensors", size: Int64(data.count), sha256: TopicAnalysis.fingerprint("test weights"))
        let valid = try await ModelInstaller.verify(file, file: descriptor)
        XCTAssertTrue(valid)
        try Data("bad! weights".utf8).write(to: file)
        let invalid = try await ModelInstaller.verify(file, file: descriptor)
        XCTAssertFalse(invalid)
        XCTAssertFalse(ModelFile(path: "../outside.json", size: 1).isSafe)
        XCTAssertFalse(ModelFile(path: "/outside.json", size: 1).isSafe)
        XCTAssertTrue(TopicModel.catalogue[1].canRun(memory: 24 * 1_073_741_824))
        XCTAssertFalse(TopicModel.catalogue[2].canRun(memory: 24 * 1_073_741_824))
    }

    func testLegacyPreferencesMigrateWithoutOldBackendsOrThresholds() throws {
        let legacy = Data("{\"organiser\":\"ollama\",\"ollamaModel\":\"old-model\",\"organiserThreshold\":0.52,\"autoOrganise\":false}".utf8)
        let prefs = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(prefs.topicModelID, "qwen3.5-9b"); XCTAssertEqual(prefs.modelIdleSeconds, 30)
        XCTAssertFalse(prefs.autoOrganise)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        XCTAssertNil(object["organiser"]); XCTAssertNil(object["ollamaModel"]); XCTAssertNil(object["organiserThreshold"])
    }

    func testHelperUnloadsAfterIdleAndCancellationDoesNotHang() async throws {
        let script = directory.appendingPathComponent("topic-helper"), pidFile = directory.appendingPathComponent("helper.pid")
        try "#!/bin/zsh\nprint $$ > '\(pidFile.path)'\nwhile IFS= read -r line; do\n print '{\"topics\":[\"Work\"]}'\ndone\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let runtime = LocalTopicRuntime(executable: script)
        defer { runtime.unload() }
        let result = try await runtime.analyse(text: "Saved text", topics: [NoteCategory(name: "Work", description: "")], modelDirectory: directory)
        XCTAssertEqual(result.topics, ["Work"])
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), 0)
        runtime.scheduleUnload(after: 0)
        for _ in 0..<100 { if kill(pid, 0) != 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotEqual(kill(pid, 0), 0, "Unloading must release the entire helper process")
        try "#!/bin/zsh\nprint $$ > '\(pidFile.path)'\nwhile IFS= read -r line; do\n read -t 30 ignored\ndone\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let request = Task { try await runtime.analyse(text: "Another snapshot", topics: [], modelDirectory: directory) }
        try await Task.sleep(for: .milliseconds(40))
        request.cancel()
        do { _ = try await request.value; XCTFail("Expected cancellation") } catch {}
    }

    func testDeletingModelKeepsNotesAndRemovesOnlyOwnedModelFiles() throws {
        let (notes, _, controller, _) = try fixture()
        defer { controller.shutdown() }
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Keep this note")))
        let topic = controller.categories.categories[0].id
        controller.categories.setManual(topic, noteID: note.id, included: true)
        let file = notes.directory.appendingPathComponent(note.id.uuidString + ".json"), saved = try Data(contentsOf: file)
        controller.models.delete(TopicModel.catalogue[0])
        XCTAssertTrue(controller.models.installedIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), saved)
        XCTAssertEqual(controller.categories.labels(for: note.id).included, [topic])
    }

    func testFixedTopicMigrationPreservesIDsManualChoicesAndEditedDescriptions() throws {
        let topics = CategoryStore(directory: directory)
        for name in ["Mandir", "University", "Dev", "Scratchpad"] { topics.saveCategory(name: name, description: "Old description") }
        let oldIDs = topics.categories.map(\.id), note = UUID()
        topics.setManual(oldIDs[0], noteID: note, included: true)
        topics.setManual(oldIDs[2], noteID: note, included: false)
        let originalLabels = topics.labels(for: note)
        XCTAssertTrue(topics.configureFixedTopics())
        XCTAssertEqual(Array(topics.categories.prefix(4).map(\.id)), oldIDs)
        XCTAssertEqual(topics.categories.map(\.name), ["Mandir", "University", "Dev", "Scratchpad", "Prompt"])
        XCTAssertEqual(topics.labels(for: note), originalLabels)
        XCTAssertFalse(topics.saveCategory(name: "Invented", description: ""))
        XCTAssertTrue(topics.saveCategory(id: oldIDs[0], name: "Mandir", description: "A later user refinement"))
        XCTAssertTrue(topics.configureFixedTopics())
        XCTAssertEqual(topics.categories[0].description, "A later user refinement")
        XCTAssertEqual(CategoryStore(directory: directory).labels(for: note), originalLabels)
    }

    func testPromptCanCombineWithAnyDomainAndScratchpadIsOnlyFallback() throws {
        let topics = CategoryStore(directory: directory)
        XCTAssertTrue(topics.configureFixedTopics())
        let note = UUID()
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["Mandir", "Prompt", "Scratchpad"]), noteID: note))
        XCTAssertEqual(topics.names(for: note), "Mandir, Prompt")
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["University", "Dev", "Prompt"]), noteID: note))
        XCTAssertEqual(topics.names(for: note), "University, Dev, Prompt")
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["Prompt"]), noteID: note))
        XCTAssertEqual(topics.names(for: note), "Scratchpad, Prompt")
        XCTAssertTrue(try topics.applyTopics(.init(topics: []), noteID: note))
        XCTAssertEqual(topics.names(for: note), "Scratchpad")
        XCTAssertTrue(try topics.applyTopics(.init(topics: []), noteID: note, useFallback: false))
        XCTAssertTrue(topics.labels(for: note).automatic.isEmpty)
        let mandir = try XCTUnwrap(topics.categories.first { $0.name == "Mandir" }).id
        topics.setManual(mandir, noteID: note, included: true)
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["Prompt"]), noteID: note))
        XCTAssertEqual(topics.names(for: note), "Mandir, Prompt")
    }

    func testFullDescriptionsReachTheModelAndUnknownTopicsAreRejectedAtomically() throws {
        let topics = CategoryStore(directory: directory)
        XCTAssertTrue(topics.configureFixedTopics())
        let data = try TopicAnalysis.requestData(passage: "A fictional mandir AI prompt", topics: topics.organisationTopics)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sent = try XCTUnwrap(object["allowedTopics"] as? [[String: String]])
        XCTAssertEqual(sent.map { $0["description"]! }, topics.organisationTopics.map(\.description))
        XCTAssertTrue(sent.allSatisfy { $0["description"]!.count > 80 })
        let note = UUID()
        XCTAssertTrue(try topics.applyTopics(.init(topics: ["Dev"]), noteID: note))
        let old = topics.labels(for: note)
        XCTAssertThrowsError(try topics.applyTopics(.init(topics: ["Dev", "New invented topic"]), noteID: note))
        XCTAssertEqual(topics.labels(for: note), old)
        XCTAssertEqual(topics.categories.count, 5)
    }

    func testExpandedCatalogueHasPinnedSourcesTiersAndLicenceLinks() {
        let models = TopicModel.catalogue
        XCTAssertEqual(models.count, 11)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertTrue(models.contains { $0.downloadBytes < 400_000_000 })
        XCTAssertEqual(Set(models.map(\.tier)), Set(ModelTier.allCases))
        XCTAssertTrue(models.allSatisfy { $0.revision.count == 40 && $0.downloadBytes > 0 && $0.sourceURL.scheme == "https" && $0.licenceURL.scheme == "https" })
    }

    func testMemoryUsesOnlyHumanLabelsAndSurvivesReloadWithoutCopyingText() throws {
        let notes = NoteStore(directory: directory.appendingPathComponent("Notes")), topics = CategoryStore(directory: directory)
        XCTAssertTrue(topics.configureFixedTopics())
        let first = try XCTUnwrap(notes.create(content: EditorStyle.plain("Unique private sabha planning volunteer rota")))
        let guess = try XCTUnwrap(notes.create(content: EditorStyle.plain("sabha planning generated guess")))
        let mandir = try XCTUnwrap(topics.categories.first { $0.name == "Mandir" }).id
        topics.setManual(mandir, noteID: first.id, included: true)
        topics.setAutomatic([mandir], noteID: guess.id)
        let bank = TopicMemoryBank(directory: directory)
        bank.seedIfNeeded(notes: notes.activeNotes, categories: topics)
        XCTAssertEqual(bank.count, 1, "Automatic predictions must not become ground truth")
        let restored = TopicMemoryBank(directory: directory)
        let examples = restored.examples(for: "sabha planning volunteer schedule", excluding: UUID(), notes: notes.activeNotes, categories: topics.organisationTopics)
        XCTAssertEqual(examples.count, 1)
        XCTAssertEqual(examples[0].includedTopics, ["Mandir"])
        XCTAssertTrue(restored.examples(for: first.text, excluding: first.id, notes: notes.activeNotes, categories: topics.organisationTopics).isEmpty)
        let stored = try String(contentsOf: directory.appendingPathComponent("topic-memory.json"))
        XCTAssertFalse(stored.contains("Unique private"), "Memory stores IDs and fingerprints, not duplicate note text")
        notes.update(first.id, content: EditorStyle.plain("Changed meaning completely"))
        restored.prune(notes: notes.activeNotes, allowedIDs: Set(topics.organisationTopics.map(\.id)))
        XCTAssertEqual(restored.count, 0)
    }

    func testMemoryClearDoesNotReseedOrRemoveManualAssignments() throws {
        let notes = NoteStore(directory: directory.appendingPathComponent("Notes")), topics = CategoryStore(directory: directory)
        XCTAssertTrue(topics.configureFixedTopics())
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Confirmed software compiler problem")))
        try topics.applyTopics(.init(topics: ["Dev"]), noteID: note.id)
        topics.confirmTopics(noteID: note.id)
        let labels = topics.labels(for: note.id), bank = TopicMemoryBank(directory: directory)
        bank.seedIfNeeded(notes: notes.activeNotes, categories: topics)
        XCTAssertEqual(bank.count, 1)
        bank.clear()
        let restored = TopicMemoryBank(directory: directory)
        restored.seedIfNeeded(notes: notes.activeNotes, categories: topics)
        XCTAssertEqual(restored.count, 0)
        XCTAssertEqual(topics.labels(for: note.id), labels)
    }

    @MainActor func testSaveSuppliesRelevantHumanMemoryWithoutLearningAutomaticOutput() async throws {
        let (notes, _, controller, probe) = try fixture()
        defer { controller.shutdown() }
        let reference = try XCTUnwrap(notes.create(content: EditorStyle.plain("Swift compiler module debugging example")))
        let dev = try XCTUnwrap(controller.categories.categories.first { $0.name == "Dev" }).id
        controller.categories.setManual(dev, noteID: reference.id, included: true)
        let target = try XCTUnwrap(notes.create(content: EditorStyle.plain("Swift compiler module error")))
        try await waitUntil { controller.organisationState.records[target.id]?.phase == .completed }
        let index = try XCTUnwrap(probe.inputs.firstIndex(of: "Swift compiler module error"))
        XCTAssertEqual(probe.examples[index].first?.includedTopics, ["Dev"])
        XCTAssertEqual(controller.memory.count, 1, "The newly predicted target must not teach itself")
    }

    @MainActor func testOrganiseAllProcessesExistingNotesWithAutosaveAIDisabled() async throws {
        let (notes, prefs, controller, probe) = try fixture()
        defer { controller.shutdown() }
        prefs.value.autoOrganise = false
        let first = try XCTUnwrap(notes.create(content: EditorStyle.plain("First existing note")))
        let second = try XCTUnwrap(notes.create(content: EditorStyle.plain("Second existing note")))
        _ = notes.create()
        let trashed = try XCTUnwrap(notes.create(content: EditorStyle.plain("Do not organise Trash")))
        notes.trash(trashed.id)
        let mandir = try XCTUnwrap(controller.categories.categories.first { $0.name == "Mandir" }).id
        controller.categories.setManual(mandir, noteID: first.id, included: true)
        let original = notes.notes
        controller.organiseAllNotes()
        XCTAssertEqual(controller.batchTotal, 2)
        try await waitUntil { !controller.isOrganisingAll }
        XCTAssertEqual(controller.batchCompleted, 2)
        XCTAssertEqual(controller.batchFailed, 0)
        XCTAssertEqual(Set(probe.inputs), [first.text, second.text])
        XCTAssertEqual(controller.categories.labels(for: first.id).included, [mandir])
        XCTAssertEqual(controller.memory.count, 1, "Bulk guesses must not become human-confirmed memory")
        XCTAssertEqual(notes.notes.map(\.text), original.map(\.text))
        XCTAssertEqual(notes.notes.map(\.updatedAt), original.map(\.updatedAt))
        controller.organiseAllNotes()
        try await waitUntil { !controller.isOrganisingAll }
        XCTAssertEqual(probe.inputs.count, 4, "An explicit run can refresh already-classified notes")
    }

    @MainActor func testCancelOrganiseAllRejectsInFlightResultAndStopsQueue() async throws {
        let probe = ProbeTopics(); probe.gated = true
        let (notes, prefs, controller, _) = try fixture(probe: probe)
        defer { controller.shutdown(); probe.release() }
        prefs.value.autoOrganise = false
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("First pending note")))
        _ = notes.create(content: EditorStyle.plain("Second pending note"))
        controller.organiseAllNotes()
        try await waitUntil { probe.waiting }
        controller.cancelOrganisation()
        probe.release()
        try await waitUntil { !controller.isOrganising }
        XCTAssertFalse(controller.isOrganisingAll)
        XCTAssertEqual(probe.inputs.count, 1)
        XCTAssertEqual(controller.batchCompleted, 0)
        XCTAssertTrue(controller.categories.labels(for: note.id).automatic.isEmpty)
    }

    @MainActor func testOrganiseAllRequiresModelWithoutDownloadingOrChangingNotes() async throws {
        let notes = NoteStore(directory: directory.appendingPathComponent("Notes"))
        let prefs = PreferencesStore(defaults: defaults); prefs.value.autoOrganise = false
        let controller = IntelligenceController(store: notes, preferences: prefs, models: TopicModelManager(directory: directory.appendingPathComponent("NoModels")))
        defer { controller.shutdown() }
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Existing note")))
        controller.organiseAllNotes()
        XCTAssertFalse(controller.isOrganisingAll)
        XCTAssertNotNil(controller.lastError)
        XCTAssertNil(controller.models.downloadingID)
        XCTAssertEqual(notes.note(note.id)?.text, note.text)
    }

    @MainActor func testBulkRunRetriesEditedSnapshotAndKeepsGoingWhenAppearanceChanges() async throws {
        let probe = ProbeTopics(); probe.gated = true
        let (notes, prefs, controller, _) = try fixture(probe: probe)
        defer { controller.shutdown(); probe.release() }
        prefs.value.autoOrganise = false
        let note = try XCTUnwrap(notes.create(content: EditorStyle.plain("Original saved text")))
        controller.organiseAllNotes()
        try await waitUntil { probe.waiting }
        prefs.value.themeID = "mocha"
        XCTAssertTrue(controller.isOrganisingAll, "Unrelated preferences must not cancel explicit organisation")
        notes.update(note.id, content: EditorStyle.plain("Updated saved text"))
        XCTAssertTrue(notes.flush())
        probe.release()
        try await waitUntil { !controller.isOrganisingAll }
        XCTAssertEqual(probe.inputs, ["Original saved text", "Updated saved text"])
        XCTAssertEqual(controller.batchCompleted, 1)
        XCTAssertEqual(controller.organisationState.records[note.id]?.contentFingerprint, TopicAnalysis.fingerprint("Updated saved text"))
    }

    func testManualDomainImmediatelyRemovesOnlyAutomaticScratchpadFallback() throws {
        let topics = CategoryStore(directory: directory)
        XCTAssertTrue(topics.configureFixedTopics())
        let id = UUID(), scratchpad = try XCTUnwrap(topics.categories.first { $0.name == "Scratchpad" }), mandir = try XCTUnwrap(topics.categories.first { $0.name == "Mandir" })
        XCTAssertTrue(topics.setAutomatic([scratchpad.id], noteID: id))
        XCTAssertTrue(topics.setManual(mandir.id, noteID: id, included: true))
        XCTAssertEqual(topics.names(for: id), "Mandir")
        topics.setManual(scratchpad.id, noteID: id, included: true)
        topics.setManual(mandir.id, noteID: id, included: true)
        XCTAssertTrue(topics.labels(for: id).included.contains(scratchpad.id), "Explicit human choices stay authoritative")
    }
}
