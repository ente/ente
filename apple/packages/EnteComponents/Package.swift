// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EnteComponents",
    platforms: [.iOS(.v16), .tvOS(.v16)],
    products: [.library(name: "EnteComponents", targets: ["EnteComponents"])],
    dependencies: [.package(path: "../EnteFonts")],
    targets: [
        .target(
            name: "EnteComponents",
            dependencies: ["EnteFonts"],
            resources: [.process("Resources")]
        )
    ]
)
