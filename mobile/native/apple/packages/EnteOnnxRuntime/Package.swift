// swift-tools-version: 5.9

// Ente's pinned custom ONNX Runtime static XCFramework for iOS (CoreML and
// CPU; device and ARM64 Simulator). SPM downloads the release ZIP, verifies
// its checksum (a plain SHA-256 of the archive, published in the release's
// SHA256SUMS asset), and links the correct slice into the app.
//
// The Rust side (ente-ensu's iOS `ort-sys` dependency) is built with
// "disable-linking" so that it neither downloads nor bundles any other ONNX
// Runtime; the symbols resolve against this framework at app link time.
//
// See mobile/native/onnxruntime/README.md for the release bump checklist.
import PackageDescription

let package = Package(
    name: "EnteOnnxRuntime",
    products: [
        .library(name: "EnteOnnxRuntime", targets: ["onnxruntime"])
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/laurens-pilot/ort-packaging/releases/download/ort-1.27.0-r2/onnxruntime-coreml-ios-1.27.0-r2.zip",
            checksum: "87f27a8d899ff9dbea29a0eac99e08d58a854b0d58542cc131de16f029bb8d5f"
        )
    ]
)
