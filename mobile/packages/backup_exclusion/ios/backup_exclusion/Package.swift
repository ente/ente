// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "backup_exclusion",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "backup-exclusion", targets: ["backup_exclusion"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "backup_exclusion",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
