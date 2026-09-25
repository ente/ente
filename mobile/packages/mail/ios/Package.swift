// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MailCore",
    platforms: [.iOS(.v13)],
    products: [.library(name: "MailCore", targets: ["MailCore"])],
    targets: [
        .target(
            name: "MailCore",
            path: "ente_mail/Sources/ente_mail",
            exclude: ["MailPlugin.swift"]
        ),
        .testTarget(
            name: "MailCoreTests",
            dependencies: ["MailCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
