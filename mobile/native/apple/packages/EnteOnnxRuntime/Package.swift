// swift-tools-version: 5.9

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
            url: "https://github.com/laurens-pilot/ort-packaging/releases/download/ort-1.27.0-r3/onnxruntime-coreml-ios-1.27.0-r3.zip",
            checksum: "b8c450fe29c6517789b6a31e909c0469fac2aa416b4830f2adc7c4f9b4f33f89"
        )
    ]
)
