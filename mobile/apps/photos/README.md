# Mobile app for Ente Photos

Source code for our flagship mobile app. For us, this is our most important client app. This is where Ente started. This is what had the [first commit](https://github.com/ente/ente/commit/a8cdc811fd20ca4289d8e779c97f08ef5d276e37).

    commit a8cdc811fd20ca4289d8e779c97f08ef5d276e37
    Author: Vishnu Mohandas <v****@****.***>
    Date:   Wed Mar 25 01:29:36 2020 +0530

        Hello world

To know more about Ente, see [our main README](../../../README.md) or visit [ente.com](https://ente.com).

To use Ente Photos on the web, see [web](../../../web/README.md). To use Ente Photos on the desktop, see [desktop](../../../desktop/README.md). There is a also a [CLI tool](../../../cli/README.md) for easy / automated exports.

If you're looking for Ente Auth instead, see [auth](../auth/README.md).

## 📲 Installation

### Android

The [GitHub releases](https://github.com/ente/ente/releases?q=photos-v1) contain APKs, built straight from source. The latest build is available at [ente.com/apk](https://ente.com/apk). These builds keep themselves updated, without relying on third party stores.

You can alternatively install the build from PlayStore or F-Droid.

<a href="https://play.google.com/store/apps/details?id=io.ente.photos">
  <img height="59" src="../../../.github/assets/play-store-badge.png">
</a>
<a href="https://f-droid.org/packages/io.ente.photos.fdroid/">
  <img height="59" src="../../../.github/assets/f-droid-badge.png">
</a>

### iOS

<a href="https://apps.apple.com/in/app/ente-photos/id1542026904">
  <img height="59" src="../../../.github/assets/app-store-badge.svg">
</a>

## 🧑‍💻 Building from source

1. Install [Flutter v3.38.10](https://flutter.dev/docs/get-started/install) and [Rust](https://www.rust-lang.org/tools/install).

2. Install dependencies and generate Rust bindings using one of these methods:
   - **Using Flutter:** From any folder inside `mobile/`, run `flutter pub get --enforce-lockfile`, then from `rust/`, run `cargo codegen frb`.
   - **Using Melos:** Install Melos with `dart pub global activate melos`, then from any folder inside `mobile/`, run `melos bootstrap` and `melos run codegen:rust`.

3. Run the app:
   - Android: `flutter run --flavor independent`
   - iOS: `flutter run`

> [!NOTE]
>
> Re-run `cargo codegen frb` whenever the FRB-exported surface under `rust/bindings/frb/` changes. Internal Rust changes (function bodies, private helpers) are picked up by the normal Flutter build.
>
> From anywhere in the repo:
>
> ```sh
> (cd "$(git rev-parse --show-toplevel)/rust" && cargo codegen frb)
> ```

To build a release APK, [setup your keystore](https://docs.flutter.dev/deployment/android#create-an-upload-keystore) and run `flutter build apk --release --flavor independent`. For iOS, use `flutter build ios`.

### Configurable self-hosted Android build

Use the checked-in wrapper to build an Android APK with a default Museum origin
that can later be changed through the guarded Server Settings page:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://museum.example"
./scripts/build_self_hosted_android.sh --debug
```

The endpoint requirements and optional `FLUTTER_BIN` and `DART_BIN` overrides
match the configurable iOS wrapper below. Run
`./scripts/build_self_hosted_android.sh --validate-only` to validate and
canonicalize the endpoint without starting a build.

The wrapper always builds the `selfhosted` flavor as an APK, supplies
`configurableEndpoint=true` and the canonical `endpoint` as Dart defines, and rejects
caller-supplied flavors or Dart defines. The release application ID is
`com.vanton1.ente.photos.selfhosted`; debug builds inherit the repository-wide
`.debug` suffix. Existing Android flavors and their application IDs are
unchanged. Release builds use the existing Gradle signing configuration, with
the keystore path and credentials supplied through ignored `key.properties` or
the `SIGNING_*` environment variables.

### Configurable self-hosted iOS build

Use the checked-in wrapper to build an iOS app with a default Museum origin that
can later be changed through the guarded Server Settings page:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://museum.example"
./scripts/build_self_hosted_ios.sh --simulator --debug
```

`ENTE_SELF_HOSTED_ENDPOINT` is the only required input for a simulator build.
It must be an absolute HTTPS origin without credentials, a path, query, or
fragment. The wrapper canonicalizes the value and supplies both
`configurableEndpoint=true` and `endpoint`
as Dart defines. It rejects caller-supplied Dart defines and flavors so those
security and target selections cannot be overridden. On Apple-silicon
simulator builds, it also applies the repository's required arm64-only Xcode
setting to avoid linking the unsupported x86_64 Rust slice.

Run `./scripts/build_self_hosted_ios.sh --validate-only` to check the endpoint
without starting a build. `FLUTTER_BIN` and `DART_BIN` may optionally select the
repository-pinned Flutter and Dart executables when they are not on `PATH`.

The wrapper always builds the shared `selfhosted` scheme and its
`SelfHostedRunner` target. That target uses the unique bundle identifier
`com.vanton1.ente.photos.selfhosted`, embeds no Share Extension or widgets, and
has no production push, associated-domain, or app-group entitlements. The
official `Runner` target and scheme keep their existing settings and extension
dependencies.

The compiled endpoint is used only when no valid server binding exists. An
in-place upgrade from an earlier locked build retains its binding, account, and
photos. To change it, open **Server** in authenticated Settings or tap the
current-server link on a signed-out screen. The app validates the candidate
before changing anything and requires confirmation plus local logout for a
signed-in account.

For a signed physical-device build, first sign in to an Apple ID under Xcode's
Accounts settings and create an Apple Development certificate. Then provide
the development-team identifier shown by Xcode:

```sh
export ENTE_IOS_DEVELOPMENT_TEAM="YOURTEAMID"
export ENTE_IOS_DEVICE_ID="YOUR_CONNECTED_IPHONE_ID"
./scripts/build_self_hosted_ios.sh --debug
```

Automatic signing may create or update the development provisioning profile
for the self-hosted bundle identifier. `ENTE_IOS_DEVICE_ID` is optional after
the phone is registered, but setting it to the identifier shown by
`xcrun xcdevice list` lets Xcode register and provision a connected phone on
the first build. Use `--no-codesign` to compile a device artifact without a
certificate or profile; that artifact cannot be installed until it is signed.

### Updating dependencies

After updating Flutter dependencies, run `pod install` from `ios/` on macOS and commit `ios/Podfile.lock` if it changes.

## 📝 Localization

This project uses Flutter's built-in localization system configured via `l10n.yaml`.

- Localization files are auto-generated when you run `flutter pub get`
- The base localization file is `lib/l10n/intl_en.arb`
- Generated code appears in `lib/generated/intl/`
- To manually regenerate: `flutter gen-l10n`

See [docs/translations.md](docs/translations.md) for contributing translations.

## 🏙️ Attributions

City coordinates from [Simple Maps](https://simplemaps.com/data/world-cities)

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-photos-app/localized.svg)](https://crowdin.com/project/ente-photos-app)

If you're interested in helping out with translation, please visit our [Crowdin project](https://crowdin.com/project/ente-photos-app) to get started. Thank you for your support.

If your language is not listed for translation, please [create a GitHub issue](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A) to have it added.

## 💚 Contribute

For more ways to contribute, see [CONTRIBUTING.md](../../../CONTRIBUTING.md).
