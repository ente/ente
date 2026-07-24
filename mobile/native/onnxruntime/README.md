# Custom ONNX Runtime binaries

The mobile apps use Ente's pinned custom ONNX Runtime 1.27.0 packaging build
(`ort-1.27.0-r2` from the ort-packaging repository):

- Android: WebGPU, XNNPACK, and CPU; ARM64, ARMv7, and x86_64
- iOS: CoreML and CPU; iOS 15.1+ device and ARM64 Simulator

Each platform's own package manager downloads and checksum-verifies the
binaries; there are no custom download scripts.

- **Android**: the AAR is resolved as a regular Gradle dependency
  (`io.ente.onnxruntime:onnxruntime-webgpu-android`) from an Ivy repository
  that points directly at the GitHub release. Its SHA-256 is pinned via
  Gradle dependency verification. Used by the photos app and ensu.
- **iOS (photos)**: the release ZIP is downloaded by CocoaPods as the local
  `EnteOnnxRuntime` pod (`EnteOnnxRuntime.podspec` in this directory), which
  pins its SHA-256. The `ente_photos_rust` pod's build phase exports
  `ORT_LIB_PATH` pointing at the pre-thinned static archive for the active
  platform slice, which the Rust `ort` crate links statically.
- **iOS (ensu)**: the Ensu Xcode project links the static XCFramework from
  the same ZIP through Swift Package Manager
  (`mobile/native/apple/packages/EnteOnnxRuntime/Package.swift`, a binary
  target with a pinned checksum). The Rust side builds `ort-sys` with
  `disable-linking` on iOS (see `rust/crates/ensu/Cargo.toml`), so cargo
  neither downloads nor bundles any other ONNX Runtime; symbols resolve
  against the SPM framework at app link time. Note: because of this, build
  `ente-ensu-uniffi` for iOS with `--crate-type staticlib` (as the app's
  `build-rust.sh` does); the cdylib crate type cannot link on iOS since
  nothing provides ONNX Runtime at cargo link time.

Desktop ONNX Runtime packaging is intentionally unchanged.

## Bumping the pinned release

Update the release tag, version, and SHA-256 digests (published as the
`SHA256SUMS` release asset) in each of:

1. `EnteOnnxRuntime.podspec` (this directory): `s.version`, `:http` URL, and
   `:sha256`; then run `pod install` in `mobile/apps/photos/ios`.
2. `mobile/apps/photos/android/app/build.gradle`: the
   `io.ente.onnxruntime:onnxruntime-webgpu-android` dependency version.
3. `mobile/apps/photos/android/gradle/verification-metadata.xml`: the
   component version, artifact file name, and SHA-256.
4. `mobile/native/android/apps/ensu/rust/build.gradle.kts`: the dependency
   version.
5. `mobile/native/android/apps/ensu/gradle/verification-metadata.xml`: same
   as 3.
6. `mobile/native/apple/packages/EnteOnnxRuntime/Package.swift`: the binary
   target URL and checksum (the checksum is the plain SHA-256 of the iOS
   ZIP, identical to the one used in 1).

## WebGPU rollout status

On Android, the WebGPU execution provider is opt-in at runtime
(`set_ml_execution_config` in the Rust ML bindings; the photos app currently
enables it for internal users only) and is additionally restricted to
Android 12+ (SDK 31). All other devices use the XNNPACK/CPU chain.

## Building the Rust photos crate for iOS outside Xcode

The iOS `ort` dependency does not download prebuilt binaries; the
`ente_photos_rust` build phase exports `ORT_LIB_PATH` pointing at the custom
static archive inside the `EnteOnnxRuntime` pod. For direct `cargo`
invocations against an iOS target (for example `cargo check`), run
`pod install` in `mobile/apps/photos/ios` once, then export it manually:

```sh
ORT_LIB_PATH="$PWD/mobile/apps/photos/ios/Pods/EnteOnnxRuntime/static-lib/ios-arm64" \
IPHONEOS_DEPLOYMENT_TARGET=15.1 \
cargo check -p ente-photos --target aarch64-apple-ios
```

Use the `ios-arm64-simulator` slice and `--target aarch64-apple-ios-sim` for
the Simulator. The deployment target must be at least 15.1 to match the
archive.
