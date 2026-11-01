import Foundation
import Darwin

// A private, native MLX helper isolates GPU memory and allows prompt cancellation/unloading.
// No server, downloads, or networking occur in this process.
final class LocalTopicRuntime: TopicOrganiser, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Drafts.topics", qos: .utility)
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var loadedDirectory: URL?
    private var idle: DispatchWorkItem?
    private var cancellationGeneration = 0
    private var idleGeneration = 0
    private let executable: URL?

    init(executable: URL? = nil) { self.executable = executable }
    deinit { unload() }

    func cancel() { unload() }
    func unload() {
        lock.lock()
        cancellationGeneration += 1
        idleGeneration += 1
        idle?.cancel(); idle = nil
        let running = process
        lock.unlock()
        terminate(running)
    }

    private func terminate(_ running: Process?) {
        if let running, running.isRunning {
            running.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if running.isRunning { kill(running.processIdentifier, SIGKILL) } }
        }
    }

    func scheduleUnload(after seconds: Int) {
        lock.lock()
        idle?.cancel()
        idleGeneration += 1
        let token = idleGeneration
        let task = DispatchWorkItem { [weak self] in self?.unloadIfIdle(token) }
        idle = task
        lock.unlock()
        queue.asyncAfter(deadline: .now() + .seconds(max(0, seconds)), execute: task)
    }

    private func unloadIfIdle(_ token: Int) {
        lock.lock()
        guard idleGeneration == token else { lock.unlock(); return }
        cancellationGeneration += 1
        let running = process
        lock.unlock()
        terminate(running)
    }

    func analyse(text: String, topics: [NoteCategory], memory: [TopicMemoryExample] = [], modelDirectory: URL) async throws -> TopicAnalysis {
        try Task.checkCancellation()
        let generation = lock.withLock { idle?.cancel(); idleGeneration += 1; return cancellationGeneration }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        let analysis = try request(text: text, topics: topics, memory: memory, directory: modelDirectory, generation: generation)
                        continuation.resume(returning: analysis)
                    } catch { unload(); continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.cancel() }
    }

    private func checkGeneration(_ generation: Int) throws {
        lock.lock(); let current = cancellationGeneration; lock.unlock()
        if generation != current { throw CancellationError() }
    }

    private func request(text: String, topics: [NoteCategory], memory: [TopicMemoryExample], directory: URL, generation: Int) throws -> TopicAnalysis {
        guard TopicModel.supportedHardware else { throw TopicModelError.unavailable }
        try checkGeneration(generation)
        lock.lock(); idle?.cancel(); lock.unlock()
        if loadedDirectory != directory { terminate(process) }
        if process?.isRunning != true || loadedDirectory != directory {
            if let previous = process, previous.isRunning { previous.waitUntilExit() }
            try? input?.close(); try? output?.close()
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DraftsTopicModel")
            let development = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("DraftsTopicModel")
            guard let executable = executable ?? ([bundled] + [development].compactMap { $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw TopicModelError.unavailable }
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            child.executableURL = executable
            child.arguments = [directory.path]
            child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
            child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
            try child.run()
            input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
            _ = fcntl(input!.fileDescriptor, F_SETNOSIGPIPE, 1)
            loadedDirectory = directory
            lock.lock()
            let cancelled = generation != cancellationGeneration
            if !cancelled { process = child }
            lock.unlock()
            if cancelled { terminate(child); throw CancellationError() }
        }
        guard let child = process, let input, let output else { throw TopicModelError.unavailable }
        let timeout = DispatchWorkItem { [weak self] in self?.terminate(child) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timeout)
        defer { timeout.cancel() }
        var allTopics: [String] = []
        for passage in TopicAnalysis.passages(text) {
            try checkGeneration(generation)
            guard child.isRunning else { throw TopicModelError.failed("Local AI stopped. Your note and previous topics were kept.") }
            var data = try TopicAnalysis.requestData(passage: passage, topics: topics, memory: memory); data.append(10)
            try input.write(contentsOf: data)
            var response = Data()
            while !response.contains(10) {
                let chunk = output.availableData
                guard !chunk.isEmpty, response.count + chunk.count < 64_000 else { throw TopicModelError.failed("Local AI stopped or timed out. Your saved note is safe.") }
                response.append(chunk)
            }
            struct Response: Decodable { var topics: [String]?; var error: String? }
            let result = try JSONDecoder().decode(Response.self, from: response)
            if let error = result.error { throw TopicModelError.failed(error) }
            guard let names = result.topics else { throw TopicModelError.invalidOutput }
            let validated = try TopicAnalysis(topics: names).validated(allowedTopics: topics)
            for name in validated.topics where !allTopics.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                if allTopics.count < 8 { allTopics.append(name) }
            }
        }
        try checkGeneration(generation)
        return try TopicAnalysis(topics: allTopics).validated(allowedTopics: topics)
    }
}
