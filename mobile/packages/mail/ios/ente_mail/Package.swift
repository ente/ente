// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ente_mail",
    platforms: [.iOS(.v13)],
    products: [.library(name: "ente-mail", targets: ["ente_mail"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "ente_mail",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
