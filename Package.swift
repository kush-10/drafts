// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Drafts",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Drafts", targets: ["Drafts"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0")
    ],
    targets: [
        .executableTarget(name: "Drafts"),
        .executableTarget(name: "DraftsTopicModel", dependencies: [
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ]),
        .testTarget(name: "DraftsTests", dependencies: ["Drafts"])
    ],
    swiftLanguageModes: [.v5]
)
