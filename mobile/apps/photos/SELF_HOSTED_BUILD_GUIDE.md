# Configurable Self-Hosted Mobile Build Guide

This guide builds the personal Ente Photos Android and iOS applications for
a default Museum HTTPS origin. The applications can later validate and switch
to another HTTPS Museum origin through their guarded Server Settings page.

The personal applications use separate identities from the official Ente app:

- Android release package: `me.vanton.ente.photos.selfhosted`
- Android debug package: `me.vanton.ente.photos.selfhosted.debug`
- iOS bundle identifier: `com.vanton1.ente.photos.selfhosted`

The official applications can remain installed alongside these builds.

## 1. Endpoint requirements

Use the Museum origin, without an API path:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://photos.example.com"
```

The value must:

- Use HTTPS.
- Contain only a scheme, hostname, and optional port.
- Not contain credentials, a path, query, or fragment.
- Be reachable and TLS-trusted from the Android or iOS device.

Configurable builds may intentionally use an official Ente production origin.
Earlier immutable locked builds continue to reject those origins.

Validate it without building:

```sh
cd "$(git rev-parse --show-toplevel)/mobile/apps/photos"
./scripts/build_self_hosted_android.sh --validate-only
./scripts/build_self_hosted_ios.sh --validate-only
```

## 2. Toolchain on this Mac

The project and CI use Flutter 3.38.10. This checkout currently uses the
following isolated tools:

```sh
export FLUTTER_BIN="/private/tmp/ente-flutter-3.38.10/bin/flutter"
export DART_BIN="/private/tmp/ente-flutter-3.38.10/bin/dart"

export JAVA_HOME="/Users/vanton/projects/ente-android-toolchain/jdk-17.0.19+10/Contents/Home"
export ANDROID_HOME="/Users/vanton/projects/ente-android-toolchain/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="/Users/vanton/.cargo/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$(dirname "$FLUTTER_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
```

`/private/tmp` may be cleared after a reboot. Restore the pinned Flutter
checkout or change `FLUTTER_BIN` and `DART_BIN` if those paths no longer exist.

From the repository root, install the lockfile-pinned Flutter dependencies when
needed:

```sh
cd mobile
"$FLUTTER_BIN" pub get --enforce-lockfile
cd apps/photos
```

Put rustup's `cargo` and `rustc` before incompatible Homebrew installations on
`PATH`, as shown above.

## 3. Android builds

Run Android commands from the Photos application directory:

```sh
cd "$(git rev-parse --show-toplevel)/mobile/apps/photos"
export ENTE_SELF_HOSTED_ENDPOINT="https://photos.example.com"
```

### Debug APK

```sh
./scripts/build_self_hosted_android.sh --debug
```

Output:

```text
build/app/outputs/flutter-apk/app-selfhosted-debug.apk
```

Install it on a connected emulator or USB-debugging device:

```sh
adb install -r -t build/app/outputs/flutter-apk/app-selfhosted-debug.apk
```

### Signed release APK

The personal signing material on this Mac is stored outside Git:

```text
/Users/vanton/projects/ente-android-toolchain/signing/ente-photos-selfhosted-release.jks
```

The ignored `android/key.properties` file contains only the keystore path and
alias. The generated password is stored in the macOS login Keychain under the
service `ente-photos-selfhosted-release`.

Load the password into Gradle's existing signing variables, build, and remove
the variables from the current shell:

```sh
SIGNING_PASSWORD="$(security find-generic-password -w -s ente-photos-selfhosted-release)"
export SIGNING_STORE_PASSWORD="$SIGNING_PASSWORD"
export SIGNING_KEY_PASSWORD="$SIGNING_PASSWORD"

./scripts/build_self_hosted_android.sh --release

unset SIGNING_PASSWORD SIGNING_STORE_PASSWORD SIGNING_KEY_PASSWORD
```

Do not add `--no-pub` to the final release build. Flutter must regenerate its
release-only plugin registrant so development plugins are excluded correctly.

Output:

```text
build/app/outputs/flutter-apk/app-selfhosted-release.apk
```

Install it on a connected USB-debugging device:

```sh
adb install -r build/app/outputs/flutter-apk/app-selfhosted-release.apk
```

The earlier locked release artifact built for the current local endpoint is
preserved as historical rollback evidence at:

```text
/Users/vanton/projects/ente-android-toolchain/artifacts/ente-photos-selfhosted-1.3.59-release.apk
```

Its SHA-256 is:

```text
2f5f6011035e396f7b1d3660fe7043fc509115554dcca2051e3fe5a868461fc8
```

### Optional Android artifact checks

```sh
APK="build/app/outputs/flutter-apk/app-selfhosted-release.apk"
BUILD_TOOLS="$ANDROID_HOME/build-tools/36.0.0"

"$BUILD_TOOLS/aapt2" dump badging "$APK"
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$APK"
unzip -t "$APK"
shasum -a 256 "$APK"
```

The current personal signing certificate SHA-256 fingerprint is:

```text
9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69
```

Keep the keystore and its Keychain password safe. Future APK updates for the
same package must be signed by the same key.

## 4. iOS builds

Run iOS commands from the Photos application directory:

```sh
cd "$(git rev-parse --show-toplevel)/mobile/apps/photos"
export ENTE_SELF_HOSTED_ENDPOINT="https://photos.example.com"
export PATH="$HOME/.cargo/bin:$PATH"
```

Keep rustup's proxy directory before Homebrew paths. The native Rust build can
otherwise select a different `rustc` than the `cargo` toolchain selected by
Cargokit.

### iOS Simulator

The simulator build uses ad hoc signing and does not need an Apple development
team:

```sh
./scripts/build_self_hosted_ios.sh --simulator --debug
```

Output:

```text
build/ios/Debug-selfhosted-iphonesimulator/SelfHostedRunner.app
```

Install and launch it on the booted simulator:

```sh
xcrun simctl install booted \
  build/ios/Debug-selfhosted-iphonesimulator/SelfHostedRunner.app
xcrun simctl launch booted com.vanton1.ente.photos.selfhosted
```

### Signed physical-iPhone build

First sign in to an Apple ID in Xcode and make sure an Apple Development
certificate is available. The signing Team ID is the certificate subject's
`OU`; the code in parentheses in Xcode's certificate label can instead identify
the developer. Inspect the subject when necessary:

```sh
security find-certificate -c "Apple Development" -p |
  openssl x509 -noout -subject
```

Find the phone identifier with:

```sh
xcrun xcdevice list
```

Then build for the phone:

```sh
export ENTE_IOS_DEVELOPMENT_TEAM="YOUR_TEAM_ID"
export ENTE_IOS_DEVICE_ID="YOUR_CONNECTED_IPHONE_ID"

./scripts/build_self_hosted_ios.sh --debug
```

`ENTE_IOS_DEVICE_ID` is optional after Xcode has registered the phone, but it
helps automatic signing register and provision a newly connected device.

Debug device output:

```text
build/ios/Debug-selfhosted-iphoneos/SelfHostedRunner.app
```

For a signed release device build:

```sh
./scripts/build_self_hosted_ios.sh --release
```

Release device output:

```text
build/ios/Release-selfhosted-iphoneos/SelfHostedRunner.app
```

Install the `.app` through Xcode's Devices and Simulators window. With a recent
Xcode, it can also be installed from the command line:

```sh
xcrun devicectl device install app \
  --device "$ENTE_IOS_DEVICE_ID" \
  build/ios/Debug-selfhosted-iphoneos/SelfHostedRunner.app
xcrun devicectl device process launch \
  --device "$ENTE_IOS_DEVICE_ID" \
  com.vanton1.ente.photos.selfhosted
```

An unpaid Personal Team produces a short-lived provisioning profile. Rebuild
and reinstall the application when that profile expires; signing through a
separate self-hosted bundle identifier does not replace the official Ente app.

Use `--no-codesign` only when a non-installable device artifact is explicitly
needed for later signing.

## 5. Server defaults, upgrades, and switching

`ENTE_SELF_HOSTED_ENDPOINT` becomes the clean-install default. Once the app has
a valid stored server binding, that binding wins over defaults supplied by
later builds. Consequently:

- Installing a later configurable build with the same application identity
  preserves its server binding, account, and photos. This applies to future
  Android builds using `me.vanton.ente.photos.selfhosted` and to iOS builds
  using the existing self-hosted bundle identifier.
- The earlier Android package `com.vanton1.ente.photos.selfhosted` is a separate
  application. Moving to the renamed Android package is a clean install and
  does not migrate its app-local binding, account, keys, or queued work. Sync
  important work first, then log in and download the cloud library again.
- Rebuilding with a different default does not silently migrate an existing
  installation.
- A clean install binds itself to the compiled default on first launch.

To change the active server at runtime:

1. Open **Server** in authenticated Settings, or tap the current-server link on
   the landing, account-creation, or login screen.
2. Enter one canonical HTTPS origin and choose **Validate server**. The app
   performs a fresh anonymous `/ping` request without credentials or redirects.
3. If signed in, review the old and new origins, scroll through the warning,
   and confirm. The app stops current account work, clears local account state,
   stores the new binding, and returns to sign-in.
4. Register or log in on the selected server.

A failed validation leaves the account and binding untouched. The switch
clears app-local account and queued-work state but does not delete media from
the old server or the device's photo library. Sync any important pending work
before confirming.

On iOS, rollback to an earlier locked artifact is safe before a switch when its
compiled endpoint matches the retained binding. After changing the binding, an
older locked artifact for another origin fails closed; reinstall it or clear
that app's data only if you intentionally accept losing local app state.

The preserved locked Android artifact uses the old package identity, so it is
not an in-place rollback for the renamed app. Returning to it requires
uninstalling `me.vanton.ente.photos.selfhosted`, installing the old package, and
logging in again. Either Android uninstall loses that package's app-local state;
server-side encrypted media remains available through its Museum account.

## 6. Private-server connectivity

Before debugging the application, verify that the target device can:

- Resolve the Museum hostname.
- Reach the private network or Tailscale tailnet hosting Museum and MinIO.
- Trust the HTTPS certificate.
- Receive signed MinIO upload and download URLs that are reachable from the
  device.

The active stored binding constrains authenticated Museum traffic.
Museum-provided signed object-storage URLs continue through the separate upload
and download clients.
