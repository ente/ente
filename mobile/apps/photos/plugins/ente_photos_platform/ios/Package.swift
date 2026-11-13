// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PhotosPlatformCore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PhotosPlatformCore", targets: ["PhotosPlatformCore"])
    ],
    targets: [
        .target(
            name: "PhotosPlatformCore",
            path: "Sources/PhotosPlatformCore"
        )
    ],
    swiftLanguageVersions: [.v5]
)
