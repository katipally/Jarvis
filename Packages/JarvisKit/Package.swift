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
        .testTarget(name: "JStoreTests", dependencies: ["JStore"]),
        .testTarget(name: "JAgentTests", dependencies: ["JAgent"]),
        .testTarget(name: "JMemoryTests", dependencies: ["JMemory"]),
        .testTarget(name: "JProactiveTests", dependencies: ["JProactive"]),
    ]
)
