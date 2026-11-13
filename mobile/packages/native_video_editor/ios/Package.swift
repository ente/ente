// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VideoEditorCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "VideoEditorCore", targets: ["VideoEditorCore"])
    ],
    targets: [
        .target(
            name: "VideoEditorCore",
            path: "Classes",
            exclude: ["NativeVideoEditorPlugin.swift"]
        ),
        .testTarget(
            name: "VideoEditorCoreTests",
            dependencies: ["VideoEditorCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
