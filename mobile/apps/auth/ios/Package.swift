// swift-tools-version: 5.9
import PackageDescription

// Flutter-independent tests for the extension's production storage and generator.
let package = Package(
    name: "AuthAutoFillCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AuthAutoFillCore", path: "AutoFill",
            exclude: ["CredentialProviderViewController.swift",
                      "Info.plist", "AutoFill.entitlements", "AutoFill.xcconfig"],
            sources: ["AutoFillModels.swift", "AutoFillStore.swift", "TOTP.swift"]
        ),
        .testTarget(name: "AuthAutoFillCoreTests", dependencies: ["AuthAutoFillCore"], path: "AutoFillTests"),
    ]
)
