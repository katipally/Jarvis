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
        .library(name: "JKnowledge", targets: ["JKnowledge"]),
        .library(name: "JWorlds", targets: ["JWorlds"]),
        .library(name: "JMind", targets: ["JMind"]),
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
        // Knowledge core (v0.4): episode → fact → typed entities + bi-temporal
        // edges, hybrid retrieval.
        .target(
            name: "JKnowledge",
            dependencies: ["JStore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        // World connectors (v0.4 M2): each data source syncs incrementally via
        // a checkpoint cursor — text worlds emit episodes, structured worlds
        // emit deterministic graph ops.
        .target(
            name: "JWorlds",
            dependencies: ["JStore", "JKnowledge", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Decision-engine primitives (v0.4 M3): dedupe window, token buckets,
        // promotion budget, staged delivery planning, facet stability engine.
        // Pure and deterministic — every function takes an injected `now`.
        .target(name: "JMind"),
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
        .testTarget(name: "JKnowledgeTests", dependencies: ["JKnowledge"]),
        .testTarget(name: "JWorldsTests", dependencies: ["JWorlds"]),
        .testTarget(name: "JMindTests", dependencies: ["JMind"]),
        .testTarget(name: "JProactiveTests", dependencies: ["JProactive"]),
        .testTarget(name: "JLocalTests", dependencies: ["JLocal"]),
    ]
)
