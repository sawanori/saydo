// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SaydoAI",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "SaydoAI", targets: ["SaydoAI"])
    ],
    dependencies: [
        .package(path: "../SaydoCore")
    ],
    targets: [
        .target(
            name: "SaydoAI",
            dependencies: [
                .product(name: "SaydoCore", package: "SaydoCore")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SaydoAITests",
            dependencies: ["SaydoAI"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
