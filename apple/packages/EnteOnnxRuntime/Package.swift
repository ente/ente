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
            url: "https://github.com/ente/ort-packaging/releases/download/ort-1.28.1-r1/onnxruntime-coreml-ios-1.28.1-r1.zip",
            checksum: "774b986bdd8a9f729a3e80ce7f7e7e695f0387be6f66633feaa9835c05e8557e"
        )
    ]
)
