// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LotsawaCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        
        .library(
            name: "LotsawaCore",
            targets: ["LotsawaCore"]),
        .executable(
            name: "LotsawaDemo",
            targets: ["LotsawaDemo"]),
    ],
    targets: [
        .target(
            name: "LotsawaCore",
            dependencies: [],
            path: "Sources/LotsawaCore",
            exclude: [
                "dictionary.sqlite",
                "TibetanLM.mlmodelc",
                "phonetic_dictionary.json",
                "phonetic_lookup.json",
                "context_model.json",
                "word_frequency.json"
            ],
            resources: [
                .copy("lotsawa.db"),
                .process("phonetic_variations.json"),
                .process("phonetic_pairs.json"),
                .process("sumtak_rules.json"),
                .process("semantic_hints.json"),
                .process("TibetanLM.mlmodel"),
                .process("ml_vocab.json")
            ]
        ),
        .executableTarget(
            name: "LotsawaDemo",
            dependencies: ["LotsawaCore"],
            path: "Sources/LotsawaDemo"
        ),
        .testTarget(
            name: "LotsawaCoreTests",
            dependencies: ["LotsawaCore"],
            path: "Tests/LotsawaCoreTests"
        ),
    ]
)
