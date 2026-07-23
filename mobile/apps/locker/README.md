# Ente Locker

Ente's secure document storage app. An end-to-end encrypted app for storing important documents in the cloud with secure sharing capabilities.

## 🧑‍💻 Build from source

1. [Install Flutter v3.38.10](https://flutter.dev/docs/get-started/install).

2. From any folder inside `mobile/`, install the workspace dependencies with `flutter pub get --enforce-lockfile`. Then, from `rust/`, generate the Rust bindings with `cargo codegen frb`.

3. Run the app:
   - Android: `flutter run --flavor independent`
   - iOS: `flutter run`

To build a release APK, [setup your keystore](https://docs.flutter.dev/deployment/android#create-an-upload-keystore) and run `flutter build apk --release --flavor independent`. For iOS, use `flutter build ios`.

### Updating dependencies

After updating Flutter dependencies, run `pod install` from `ios/` on macOS and commit `ios/Podfile.lock` if it changes.

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-locker/localized.svg)](https://crowdin.com/project/ente-locker)

If you're interested in helping out with translation, please visit our [Crowdin project](https://crowdin.com/project/ente-locker) to get started. Thank you for your support.

If your language is not listed for translation, please [create a GitHub issue](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A) to have it added.
