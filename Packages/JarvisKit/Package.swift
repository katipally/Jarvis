// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JarvisKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "JStore", targets: ["JStore"]),
        .library(name: "JAgent", targets: ["JAgent"]),
        .library(name: "JSpeech", targets: ["JSpeech"]),
        .library(name: "JMemory", targets: ["JMemory"]),
        .library(name: "JControl", targets: ["JControl"]),
        .library(name: "JScreen", targets: ["JScreen"]),
        .library(name: "JProactive", targets: ["JProactive"]),
        .library(name: "JLocal", targets: ["JLocal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "JStore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "JAgent"),
        .target(name: "JSpeech"),
        .target(
            name: "JMemory",
            dependencies: ["JStore", "JAgent", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "JControl"),
        .target(
            name: "JScreen",
            dependencies: ["JStore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "JProactive",
            dependencies: ["JStore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        // On-device Apple Foundation Models wrappers + @Generable DTOs.
        // System frameworks only (FoundationModels, NaturalLanguage) — no deps.
        .target(name: "JLocal"),
        .testTarget(name: "JStoreTests", dependencies: ["JStore"]),
        .testTarget(name: "JAgentTests", dependencies: ["JAgent"]),
        .testTarget(name: "JMemoryTests", dependencies: ["JMemory"]),
        .testTarget(name: "JProactiveTests", dependencies: ["JProactive"]),
        .testTarget(name: "JLocalTests", dependencies: ["JLocal"]),
    ]
)
