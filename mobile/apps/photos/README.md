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

2. From any folder inside `mobile/`, install the workspace dependencies with `flutter pub get --enforce-lockfile`. Then, from `rust/`, generate the Rust bindings with `cargo codegen frb`.

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

### Updating dependencies

After updating Flutter dependencies, run `pod install` from `ios/` on macOS and commit `ios/Podfile.lock` if it changes.

## 🏙️ Attributions

City data from [GeoNames](https://www.geonames.org/), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-photos-app/localized.svg)](https://crowdin.com/project/ente-photos-app)

If you're interested in helping out with translation, please visit our [Crowdin project](https://crowdin.com/project/ente-photos-app). For more details, see the docs for the [strings package](../../packages/strings/README.md).

## 💚 Contribute

For more ways to contribute, see [CONTRIBUTING.md](../../../CONTRIBUTING.md).
