# Ensu for Android

Source code for the Ensu Android app.

To know more about Ente, see [our main README](../../../../../README.md) or visit [ente.com](https://ente.com).

## Building from source

1. Install [Android Studio](https://developer.android.com/studio), [Rust](https://www.rust-lang.org/tools/install), and CMake (e.g. `brew install cmake`).

2. Generate the Kotlin bindings:

   ```sh
   cd rust
   cargo codegen native
   ```

3. Open the project in Android Studio and run the `app` module. If the Android NDK is missing, Android Studio will prompt to install it.

That's it. Apart from the `cargo codegen`, this is a normal Android project. Gradle cross-compiles the Rust libraries to JNI `.so` files automatically when building the app.

> [!NOTE]
>
> Re-run `cargo codegen native` whenever the UniFFI-exported surface under `rust/bindings/uniffi/` changes. Internal Rust changes (function bodies, private helpers) are picked up by the normal Gradle build.
>
> From anywhere in the repo:
>
> ```sh
> (cd "$(git rev-parse --show-toplevel)/rust" && cargo codegen native)
> ```

## Terminal builds

> [!NOTE]
>
> If you'd rather not open Android Studio, this section is for you.
>
> To skip the Android Studio install entirely, see [photos/docs/android-cli.md](../../../../apps/photos/docs/android-cli.md).

Build and install a debug APK on a connected device or emulator:

```sh
cd mobile/native/android/apps/ensu
./gradlew :app:installDebug
adb shell am start -n io.ente.ensu.debug/io.ente.ensu.MainActivity
```

Release APK:

```sh
./gradlew :app:assembleRelease
```

Output: `app/build/outputs/apk/release/app-release.apk`.

Release AAB (Play Store bundle):

```sh
./gradlew :app:bundleRelease
```

Output: `app/build/outputs/bundle/release/app-release.aab`.

Release builds use a debug keystore located at `debug.keystore`. For production releases, configure your own signing keys in `app/build.gradle.kts`.
