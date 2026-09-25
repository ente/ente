// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ente_panorama_viewer",
    platforms: [.iOS("15.1")],
    products: [
        .library(name: "ente-panorama-viewer", targets: ["ente_panorama_viewer"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "ente_panorama_viewer",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [.linkedFramework("CoreMotion")]
        )
    ]
)
