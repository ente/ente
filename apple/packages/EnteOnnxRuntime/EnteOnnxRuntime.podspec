# Download vehicle for Ente's pinned custom ONNX Runtime iOS static-library
# XCFramework. CocoaPods downloads the release ZIP at `pod install` time,
# verifies its SHA-256, and caches it. Nothing is compiled or linked here:
# the ente_photos_frb pod's build phase points the Rust `ort` crate at the
# XCFramework's static archive for the active platform via ORT_LIB_PATH.
Pod::Spec.new do |s|
  s.name     = 'EnteOnnxRuntime'
  s.version  = '1.28.1-r1'
  s.summary  = "Ente's custom prebuilt ONNX Runtime static-library XCFramework for iOS."
  s.homepage = 'https://github.com/ente/ort-packaging'
  s.authors  = { 'Ente' => 'engineering@ente.io' }
  s.license  = { :type => 'MIT', :file => 'ONNXRUNTIME-LICENSE' }
  s.source   = {
    :http   => 'https://github.com/ente/ort-packaging/releases/download/ort-1.28.1-r1/onnxruntime-coreml-ios-1.28.1-r1.zip',
    :sha256 => '774b986bdd8a9f729a3e80ce7f7e7e695f0387be6f66633feaa9835c05e8557e',
  }

  s.platform = :ios, '15.1'

  # Keep the XCFramework as downloaded, but do not declare it as a vendored
  # framework. CocoaPods is only the download/checksum vehicle; the Rust build
  # consumes the selected .a slice directly and links it into its staticlib.
  s.preserve_paths = \
    'onnxruntime.xcframework/**/*',
    'ONNXRUNTIME-LICENSE',
    'ThirdPartyNotices.txt'
end
