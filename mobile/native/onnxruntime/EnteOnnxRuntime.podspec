# Download vehicle for Ente's pinned custom ONNX Runtime iOS static
# libraries. CocoaPods downloads the release ZIP at `pod install` time,
# verifies its SHA-256, and caches it. Nothing is compiled or linked here:
# the ente_photos_rust pod's build phase points the Rust `ort` crate at the
# pre-thinned static archive for the active platform via ORT_LIB_PATH.
#
# See README.md next to this file for the release bump checklist.
Pod::Spec.new do |s|
  s.name     = 'EnteOnnxRuntime'
  s.version  = '1.27.0-r2'
  s.summary  = "Ente's custom prebuilt ONNX Runtime static libraries for iOS."
  s.homepage = 'https://github.com/laurens-pilot/ort-packaging'
  s.authors  = { 'Ente' => 'engineering@ente.io' }
  s.license  = { :type => 'MIT', :file => 'ONNXRUNTIME-LICENSE' }
  s.source   = {
    :http   => 'https://github.com/laurens-pilot/ort-packaging/releases/download/ort-1.27.0-r2/onnxruntime-coreml-ios-1.27.0-r2.zip',
    :sha256 => '87f27a8d899ff9dbea29a0eac99e08d58a854b0d58542cc131de16f029bb8d5f',
  }

  s.platform = :ios, '15.1'

  # Keep only the pre-thinned per-slice static archives; the XCFramework in
  # the ZIP is not used (the Rust build consumes the .a files directly).
  s.preserve_paths = \
    'static-lib/**/*',
    'ONNXRUNTIME-LICENSE',
    'ThirdPartyNotices.txt'
end
