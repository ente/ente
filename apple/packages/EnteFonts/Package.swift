// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EnteFonts",
    platforms: [.iOS("15.1"), .tvOS(.v16)],
    products: [.library(name: "EnteFonts", targets: ["EnteFonts"])],
    targets: [
        .target(
            name: "EnteFonts",
            resources: [.process("Resources")]
        )
    ]
)
