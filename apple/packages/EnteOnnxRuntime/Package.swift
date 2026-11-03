// swift-tools-version: 6.0

// Ente's pinned custom ONNX Runtime static-library XCFramework for iOS
// (CoreML and CPU; device and ARM64 Simulator). SPM downloads the release ZIP, verifies
// its checksum (a plain SHA-256 of the archive, published in the release's
// SHA256SUMS asset), and links the correct slice into the app.
//
// The Rust side (ente-ensu's iOS `ort-sys` dependency) is built with
// "disable-linking" so that it neither downloads nor bundles any other ONNX
// Runtime; the symbols resolve against this static library at app link time.
import PackageDescription

let package = Package(
    name: "EnteOnnxRuntime",
    products: [
        .library(name: "EnteOnnxRuntime", targets: ["onnxruntime"])
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            url:
                "https://github.com/ente/ort-packaging/releases/download/ort-1.31.0-r1/onnxruntime-coreml-ios-1.31.0-r1.zip",
            checksum: "4e4b12ce37e4a5c971cc758c96446b067c8e25818384e85aeed6be15decd3b86"
        )
    ]
)
