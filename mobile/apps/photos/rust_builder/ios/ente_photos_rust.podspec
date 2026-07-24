#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ente_photos_rust.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ente_photos_rust'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.1'

  # Flutter.framework does not contain an i386 slice, and ONNX Runtime 1.27
  # does not publish an x86_64 iOS Simulator binary.
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # Point the Rust `ort` crate at the custom prebuilt ONNX Runtime static
    # archive for the active platform (downloaded and SHA-256 verified by
    # CocoaPods as the EnteOnnxRuntime pod), then run the Cargokit build.
    # The build_pod.sh arguments are the relative path to the `rust` folder
    # and the name of the Rust library.
    :script => <<-SCRIPT,
      set -e
      case "$PLATFORM_NAME" in
        iphoneos)        ort_slice=ios-arm64 ;;
        iphonesimulator) ort_slice=ios-arm64-simulator ;;
        *) echo "error: unsupported platform for ONNX Runtime: $PLATFORM_NAME" >&2; exit 1 ;;
      esac
      export ORT_LIB_PATH="$PODS_ROOT/EnteOnnxRuntime/static-lib/$ort_slice"
      if [ ! -f "$ORT_LIB_PATH/libonnxruntime.a" ]; then
        echo "error: $ORT_LIB_PATH/libonnxruntime.a is missing; run 'pod install'" >&2
        exit 1
      fi
      unset ORT_IOS_XCFWK_PATH ORT_IOS_XCFWK_LOCATION
      sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../../../rust/bindings/frb/photos ente_photos_rust
    SCRIPT
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let Xcode know that the static library linked below is created by this
    # build step.
    :output_files => ["${BUILT_PRODUCTS_DIR}/libente_photos_rust.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # ONNX Runtime 1.27 supports only the ARM64 iOS Simulator slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    # Root the primary Flutter Rust Bridge dispatcher so the linker pulls in
    # the bridge and its transitive FFI exports without force-loading ONNX
    # Runtime's duplicate protobuf objects.
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '${BUILT_PRODUCTS_DIR}/libente_photos_rust.a',
      '-lc++',
      '-Wl,-u,_frb_pde_ffi_dispatcher_primary',
    ].join(' '),
  }
end
