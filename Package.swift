// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Drafts",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Drafts", targets: ["Drafts"])],
    targets: [
        .executableTarget(name: "Drafts"),
        .testTarget(name: "DraftsTests", dependencies: ["Drafts"])
    ]
)
