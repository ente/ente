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
            path: "Classes",
            exclude: ["PhotosPlatformPlugin.swift"]
        ),
        .target(name: "MlProcessLockCore"),
        .testTarget(
            name: "PhotosPlatformCoreTests",
            dependencies: ["MlProcessLockCore"],
            path: "Tests/PhotosPlatformCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
