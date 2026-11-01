import Foundation
import Combine
import CryptoKit

enum ModelTier: String, CaseIterable, Identifiable {
    case lightweight = "Lightweight", balanced = "Balanced", larger = "Larger"
    var id: String { rawValue }
}

struct TopicModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let repository: String
    let revision: String
    let downloadBytes: Int64
    let minimumMemoryGB: Int

    static let catalogue: [Self] = [
        .init(id: "qwen3.5-4b", name: "Qwen 3.5 4B", repository: "mlx-community/Qwen3.5-4B-4bit",
              revision: "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c", downloadBytes: 3_061_129_077, minimumMemoryGB: 12),
        .init(id: "qwen3.5-9b", name: "Qwen 3.5 9B", repository: "mlx-community/Qwen3.5-9B-MLX-4bit",
              revision: "938d8919941c6e7efd3c7150eff7fe9d12afa631", downloadBytes: 5_977_071_067, minimumMemoryGB: 24),
        .init(id: "qwen3.5-27b", name: "Qwen 3.5 27B", repository: "mlx-community/Qwen3.5-27B-4bit",
              revision: "45797d2985a12c55e6473686e9ea91b95e959553", downloadBytes: 16_081_492_155, minimumMemoryGB: 48),
        .init(id: "qwen3-0.6b", name: "Qwen 3 0.6B", repository: "mlx-community/Qwen3-0.6B-4bit",
              revision: "73e3e38d981303bc594367cd910ea6eb48349da8", downloadBytes: 349_711_765, minimumMemoryGB: 8),
        .init(id: "qwen3.5-0.8b", name: "Qwen 3.5 0.8B", repository: "mlx-community/Qwen3.5-0.8B-4bit",
              revision: "da28692b5f139cb0ec58a356b437486b7dac7462", downloadBytes: 652_027_143, minimumMemoryGB: 8),
        .init(id: "llama3.2-1b", name: "Llama 3.2 1B Instruct", repository: "mlx-community/Llama-3.2-1B-Instruct-4bit",
              revision: "08231374eeacb049a0eade7922910865b8fce912", downloadBytes: 712_575_975, minimumMemoryGB: 8),
        .init(id: "gemma3-1b", name: "Gemma 3 1B", repository: "mlx-community/gemma-3-1b-it-4bit",
              revision: "2d44e83dc9e80843d22fb941d3d699a0b1351aa6", downloadBytes: 767_171_778, minimumMemoryGB: 8),
        .init(id: "qwen3-1.7b", name: "Qwen 3 1.7B", repository: "mlx-community/Qwen3-1.7B-4bit",
              revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e", downloadBytes: 982_341_391, minimumMemoryGB: 8),
        .init(id: "qwen3.5-2b", name: "Qwen 3.5 2B", repository: "mlx-community/Qwen3.5-2B-4bit",
              revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207", downloadBytes: 1_749_079_691, minimumMemoryGB: 8),
        .init(id: "llama3.2-3b", name: "Llama 3.2 3B Instruct", repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
              revision: "7f0dc925e0d0afb0322d96f9255cfddf2ba5636e", downloadBytes: 1_824_807_894, minimumMemoryGB: 12),
        .init(id: "gemma3-4b", name: "Gemma 3 4B", repository: "mlx-community/gemma-3-4b-it-4bit",
              revision: "93724907d4ed1745d2fe50baadf3b0b01a65abf2", downloadBytes: 3_435_205_911, minimumMemoryGB: 16)
    ]
    var tier: ModelTier {
        if ["qwen3.5-9b", "qwen3.5-27b"].contains(id) { return .larger }
        return downloadBytes < 1_800_000_000 ? .lightweight : .balanced
    }
    var recommendation: String? {
        switch id {
        case "qwen3.5-2b": return "Lightweight choice"
        case "qwen3.5-9b": return "Recommended · 24 GB+"
        default: return nil
        }
    }
    var guidance: String {
        switch tier {
        case .lightweight: return "Smaller download and memory footprint; review ambiguous topic assignments."
        case .balanced: return "A middle-size option for everyday notes."
        case .larger: return "More memory and longer loading; useful for mixed or technical notes."
        }
    }
    var sourceURL: URL { URL(string: "https://huggingface.co/\(repository)/tree/\(revision)")! }
    var licence: String {
        if id.hasPrefix("llama") { return "Llama 3.2 terms" }
        if id.hasPrefix("gemma") { return "Gemma terms" }
        return "Apache 2.0"
    }
    var licenceURL: URL {
        if id.hasPrefix("llama") { return URL(string: "https://www.llama.com/llama3_2/license/")! }
        if id.hasPrefix("gemma") { return URL(string: "https://ai.google.dev/gemma/terms")! }
        return URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
    }
    static var supportedHardware: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    func canRun(memory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Bool {
        Self.supportedHardware && memory >= UInt64(minimumMemoryGB) * 1_073_741_824
    }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
}

struct ModelFile: Codable, Sendable {
    var path: String
    var size: Int64
    var sha256: String?
    var isSafe: Bool {
        !path.isEmpty && !path.contains("/") && !path.contains("\\") && !path.hasPrefix(".") &&
        ["json", "jinja", "safetensors"].contains(URL(fileURLWithPath: path).pathExtension)
    }
}

private struct InstalledModel: Codable {
    var model: TopicModel
    var files: [ModelFile]
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var lastReport = Date.distantPast
    init(_ onProgress: @escaping @Sendable (Int64) -> Void) { self.onProgress = onProgress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let shouldReport = lock.withLock {
            guard Date().timeIntervalSince(lastReport) >= 0.1 || totalBytesWritten == totalBytesExpectedToWrite else { return false }
            lastReport = Date(); return true
        }
        if shouldReport { onProgress(totalBytesWritten) }
    }
}

enum ModelInstaller {
    // This is the only network path: it runs solely after an explicit Download click.
    static func install(_ model: TopicModel, root: URL,
                        progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = root.appendingPathComponent(model.id + ".partial", isDirectory: true)
        guard (try? staging.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw TopicModelError.failed("Unsafe download directory.") }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let api = URL(string: "https://huggingface.co/api/models/\(model.repository)/tree/\(model.revision)?recursive=true&limit=1000")!
        let (data, response) = try await session.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TopicModelError.failed("Couldn’t read the model download manifest. Try again.") }
        struct Entry: Decodable {
            struct LFS: Decodable { var oid: String }
            var type: String; var path: String; var size: Int64; var lfs: LFS?
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        let files = entries.filter { $0.type == "file" }.map { ModelFile(path: $0.path, size: $0.size, sha256: $0.lfs?.oid) }.filter(\.isSafe)
        guard files.contains(where: { $0.path == "config.json" }), files.contains(where: { $0.path == "tokenizer.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") }),
              files.reduce(Int64(0), { $0 + $1.size }) == model.downloadBytes else { throw TopicModelError.failed("The pinned model manifest is incomplete. No model was installed.") }
        let free = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        let existing = files.reduce(Int64(0)) { total, file in
            let size = (try? fm.attributesOfItem(atPath: staging.appendingPathComponent(file.path).path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + (size == file.size ? size : 0)
        }
        guard free > model.downloadBytes - existing + 512_000_000 else { throw TopicModelError.failed("Not enough disk space for this model. Free some space and retry.") }
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.path)
            if try await verify(destination, file: file) { completed += file.size; continue }
            let offset = completed
            let delegate = ModelDownloadProgress { bytes in
                Task { @MainActor in progress(min(1, Double(offset + bytes) / Double(model.downloadBytes))) }
            }
            let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/\(file.path)")!
            let (temporary, response) = try await session.download(from: url, delegate: delegate)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TopicModelError.failed("Model download failed. Retry keeps already verified files.") }
            guard try await verify(temporary, file: file) else { throw TopicModelError.failed("Model download failed verification. Retry the download.") }
            try Task.checkCancellation()
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: temporary, to: destination)
            completed += file.size
            await progress(Double(completed) / Double(model.downloadBytes))
        }
        try Task.checkCancellation()
        try JSONEncoder().encode(InstalledModel(model: model, files: files)).write(to: staging.appendingPathComponent("installed.json"), options: .atomic)
        let destination = root.appendingPathComponent(model.id, isDirectory: true)
        // A repair replaces only this catalogue-owned model, after the new files verify.
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
    }

    static func verify(_ url: URL, file: ModelFile) async throws -> Bool {
        let verification = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == file.size else { return false }
            guard let expected = file.sha256 else { return true }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected
        }
        return try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
    }
}

final class TopicModelManager: ObservableObject {
    let directory: URL
    let runtime: any TopicOrganiser
    @Published private(set) var installedIDs = Set<String>()
    @Published private(set) var partialIDs = Set<String>()
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published var lastError: String?
    private var download: Task<Void, Never>?
    var onModelRemoved: ((String) -> Void)?

    init(directory: URL? = nil, runtime: (any TopicOrganiser)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Drafts/Models", isDirectory: true)
        self.runtime = runtime ?? LocalTopicRuntime()
        refreshInstalled()
    }
    deinit { download?.cancel(); runtime.unload() }

    func refreshInstalled() {
        installedIDs = Set(TopicModel.catalogue.filter { model in
            let root = directory.appendingPathComponent(model.id)
            guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = try? Data(contentsOf: root.appendingPathComponent("installed.json")),
                  let manifest = try? JSONDecoder().decode(InstalledModel.self, from: data), manifest.model == model,
                  manifest.files.contains(where: { $0.path == "config.json" }),
                  manifest.files.contains(where: { $0.path == "tokenizer.json" }),
                  manifest.files.contains(where: { $0.path.hasSuffix(".safetensors") }),
                  manifest.files.reduce(Int64(0), { $0 + $1.size }) == model.downloadBytes else { return false }
            return manifest.files.allSatisfy { file in
                guard file.isSafe, let values = try? root.appendingPathComponent(file.path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true && Int64(values.fileSize ?? -1) == file.size
            }
        }.map(\.id))
        partialIDs = Set(TopicModel.catalogue.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.id + ".partial").path) ||
            (!installedIDs.contains($0.id) && FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.id).path))
        }.map(\.id))
    }

    func installedDirectory(for id: String) -> URL? {
        installedIDs.contains(id) ? directory.appendingPathComponent(id, isDirectory: true) : nil
    }

    func startDownload(_ model: TopicModel) {
        guard downloadingID == nil, !installedIDs.contains(model.id), model.canRun() else { return }
        downloadingID = model.id; downloadProgress = 0; lastError = nil
        download = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { downloadingID = nil; download = nil; refreshInstalled() }
            do {
                try await ModelInstaller.install(model, root: directory) { [weak self] value in self?.downloadProgress = value }
            } catch is CancellationError { /* Verified partial files remain for retry. */ }
            catch { if !Task.isCancelled { lastError = error.localizedDescription } }
        }
    }

    func cancelDownload() { download?.cancel() }

    func delete(_ model: TopicModel) {
        guard downloadingID != model.id else { return }
        onModelRemoved?(model.id)
        runtime.unload()
        do {
            // Only catalogue-owned paths under the model directory, never system/HF/Ollama caches.
            for name in [model.id, model.id + ".partial"] {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            refreshInstalled(); lastError = nil
        } catch { lastError = "Couldn’t delete the downloaded model: \(error.localizedDescription)" }
    }
}
