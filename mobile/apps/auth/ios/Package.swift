// swift-tools-version: 5.9
import PackageDescription

// Lightweight, Flutter-independent tests for the generator used by the extension.
let package = Package(
    name: "AuthAutoFillCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AuthAutoFillCore", path: "AutoFill",
            exclude: ["AutoFillStore.swift", "CredentialProviderViewController.swift",
                      "Info.plist", "AutoFill.entitlements", "AutoFill.xcconfig"],
            sources: ["AutoFillModels.swift", "TOTP.swift"]
        ),
        .testTarget(name: "AuthAutoFillCoreTests", dependencies: ["AuthAutoFillCore"], path: "AutoFillTests"),
    ]
)
