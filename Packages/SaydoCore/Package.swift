// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SaydoCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "SaydoCore", targets: ["SaydoCore"])
    ],
    targets: [
        .target(
            name: "SaydoCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SaydoCoreTests",
            dependencies: ["SaydoCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
