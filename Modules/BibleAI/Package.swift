// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BibleAI",
    products: [
        .library(
            name: "BibleAI",
            targets: ["BibleAI"]
        ),
    ],
    dependencies: [
        .package(path: "../BibleDomain"),
    ],
    targets: [
        .target(
            name: "BibleAI",
            dependencies: [
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