import Foundation
#if arch(arm64)
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

private struct LocalTokenizer: MLXLMCommon.Tokenizer {
    let base: any Tokenizers.Tokenizer
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { base.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
    var bosToken: String? { base.bosToken }
    var eosToken: String? { base.eosToken }
    var unknownToken: String? { base.unknownToken }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        try base.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}

private struct LocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        // Local folder only: this API never downloads missing files.
        LocalTokenizer(base: try await AutoTokenizer.from(modelFolder: directory))
    }
}
#endif

@main
enum DraftsTopicModel {
    static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }

    static func main() async {
        #if arch(arm64)
        if CommandLine.arguments.contains("--check-runtime") {
            let value = MLXArray([1, 2, 3]) + 1
            eval(value)
            emit(["runtime": "MLX", "ready": value.asArray(Int.self) == [2, 3, 4]])
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check-config" {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
                let config = try JSONDecoder().decode(BaseConfiguration.self, from: data)
                let model = try await LLMModelFactory.shared.typeRegistry.createModel(configuration: data, modelType: config.modelType)
                if let validating = model as? any ModelConfigurationValidating { try validating.validateModelConfiguration() }
                emit(["supported": true, "modelType": config.modelType])
            } catch { emit(["supported": false, "error": error.localizedDescription]); exit(1) }
            return
        }
        guard CommandLine.arguments.count == 2 else { emit(["error": "Missing local model directory."]); return }
        do {
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let container = try await LLMModelFactory.shared.loadContainer(from: root, using: LocalTokenizerLoader())
            while let line = readLine() {
                do {
                    guard line.utf8.count < 64_000, var input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let instructions = input.removeValue(forKey: "instructions") as? String else {
                        emit(["error": "Invalid topic request."]); continue
                    }
                    let prompt = String(decoding: try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), as: UTF8.self)
                    // Never share a transcript/KV cache between notes.
                    let session = ChatSession(container, instructions: instructions,
                                              generateParameters: .init(maxTokens: 256, temperature: 0),
                                              additionalContext: ["enable_thinking": false])
                    let response = try await session.respond(to: prompt)
                    guard let output = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
                          Set(output.keys) == ["topics"], let topics = output["topics"] as? [String], topics.count <= 8 else {
                        emit(["error": "The model returned invalid topics. Previous assignments were kept."]); continue
                    }
                    emit(["topics": topics])
                } catch { emit(["error": "Local topic analysis failed. The saved note is unchanged."]) }
            }
        } catch { emit(["error": "Couldn’t load the installed MLX model. Verify the download in Settings."]) }
        #else
        emit(["error": "Local AI requires Apple Silicon."])
        #endif
    }
}
