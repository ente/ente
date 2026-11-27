// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ente_pip",
    platforms: [.iOS("15.1")],
    products: [
        .library(name: "ente-pip", targets: ["ente_pip"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "ente_pip",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
            ]
        )
    ]
)
