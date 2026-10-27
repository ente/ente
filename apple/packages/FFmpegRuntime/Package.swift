// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FFmpegRuntime",
    platforms: [.iOS("15.1")],
    products: [
        .library(name: "FFmpegRuntime", targets: ["FFmpegRuntime"])
    ],
    targets: [
        .binaryTarget(
            name: "FFmpegRuntime",
            url:
                "https://github.com/ente/ffmpeg-packaging/releases/download/9.0.2-2/ios-FFmpegRuntime.xcframework.zip",
            checksum: "b805072a453fc4f8d95fc9cad8346fb9a4759952a8ce70354cc2b750b00b1554"
        )
    ]
)
