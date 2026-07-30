# Ente Auth

Ente's 2FA app. An end-to-end encrypted, cross platform and free app for storing your 2FA codes with cloud backups. Works offline. You can even use it without signing up for an account if you don't want the cloud backups or multi-device sync.

![App Screenshots](./docs/assets/screenshots.png)

## 📲 Download

### Android

This repository's [GitHub releases](https://github.com/ente/ente/releases?q=tag%3Aauth-v4) contains APKs, built straight from source. These builds keep themselves updated, without relying on third party stores.

You can alternatively install the build from PlayStore or F-Droid.

<a href="https://play.google.com/store/apps/details?id=io.ente.auth">
  <img height="59" src="../../../.github/assets/play-store-badge.png">
</a>
<a href="https://f-droid.org/packages/io.ente.auth/">
  <img height="59" src="../../../.github/assets/f-droid-badge.png">
</a>

### iOS / Apple Silicon macOS

<a href="https://apps.apple.com/us/app/ente-authenticator/id6444121398">
  <img height="59" src="../../../.github/assets/app-store-badge.svg">
</a>

### Desktop

You can [**download**](https://github.com/ente/ente/releases?q=tag%3Aauth-v4) a native desktop app from this repository's GitHub releases. The desktop app works on Windows, Linux and macOS.

### Web

You can view your 2FA codes at [auth.ente.com](https://auth.ente.com). For adding or managing your secrets, please use our mobile or desktop app.

## 🧑‍💻 Build from source

1. [Install Flutter v3.38.10](https://flutter.dev/docs/get-started/install).

2. Pull in submodules with `git submodule update --init --recursive`

3. From any folder inside `mobile/`, install the workspace dependencies with `flutter pub get --enforce-lockfile`.

4. Run the app:
   - Android: `flutter run --flavor independent`
   - iOS: `flutter run`
   - macOS: `flutter run -d macos`

To build a release APK, [setup your keystore](https://docs.flutter.dev/deployment/android#create-an-upload-keystore) and run `flutter build apk --release --flavor independent`. For iOS, use `flutter build ios`.

If the code you're working needs to modify user facing strings, see [docs/localization](docs/localization.md).

### Updating dependencies

After updating Flutter dependencies, run `pod install` from `ios/` on macOS and commit `ios/Podfile.lock` if it changes.

## 🔩 Architecture

The architecture that powers end-to-end encrypted storage and sync of your tokens has been documented [here](../../../architecture/README.md#token-encryption).

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-authenticator-app/localized.svg)](https://crowdin.com/project/ente-authenticator-app)

If you're interested in helping out with translation, please visit our [Crowdin project](https://crowdin.com/project/ente-authenticator-app) to get started. Thank you for your support.

If your language is not listed for translation, please [create a GitHub issue](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A) to have it added.

## 🧑‍🎨 Icons

Ente Auth supports the icon pack provided by [simple-icons](https://github.com/simple-icons/simple-icons). If you wish to add more, see [docs/adding-icons](docs/adding-icons.md).

## 💚 Contribute

The best way to support this project is by checking out [Ente Photos](../mobile/README.md) or spreading the word.

For more ways to contribute, see [CONTRIBUTING.md](../../../CONTRIBUTING.md).

## ⭐️ About

To know more about Ente and the ways to get in touch or seek help, see [our main README](../../../README.md) or visit [ente.com](https://ente.com).
