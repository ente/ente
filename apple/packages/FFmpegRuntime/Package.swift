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
                "https://github.com/ente/ffmpeg-packaging/releases/download/9.0.2-1/ios-FFmpegRuntime.xcframework.zip",
            checksum: "168df3194e3918e70dd233560958cc5849e20e92dadf8587f0cf3adfa4207943"
        )
    ]
)
