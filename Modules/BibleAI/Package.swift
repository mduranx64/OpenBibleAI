// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BibleAI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "BibleAI",
            targets: ["BibleAI"]
        ),
    ],
    dependencies: [
        .package(path: "../BibleDomain"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BibleAI",
            dependencies: [
                .product(
                    name: "BibleDomain",
                    package: "BibleDomain"
                ),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [
                .enableUpcomingFeature(
                    "ApproachableConcurrency"
                ),
            ]
        ),
        .testTarget(
            name: "BibleAITests",
            dependencies: [
                "BibleAI",
                .product(
                    name: "BibleDomain",
                    package: "BibleDomain"
                ),
            ],
            swiftSettings: [
                .enableUpcomingFeature(
                    "ApproachableConcurrency"
                ),
            ]
        ),
    ]
)
