// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BibleData",
    products: [
        .library(
            name: "BibleData",
            targets: ["BibleData"]
        ),
    ],
    dependencies: [
        .package(path: "../BibleDomain"),
    ],
    targets: [
        .target(
            name: "BibleData",
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
            ],
        ),
        .testTarget(
            name: "BibleDataTests",
            dependencies: [
                "BibleData",
                .product(
                    name: "BibleDomain",
                    package: "BibleDomain"
                ),
            ],
            swiftSettings: [
                .enableUpcomingFeature(
                    "ApproachableConcurrency"
                ),
            ],
        ),
    ]
)
