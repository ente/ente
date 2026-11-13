---
title: Building mobile apps
description: Connecting to your custom self-hosted server when building the Ente mobile apps from source
---

# Mobile: Build and connect to self-hosted server

The up to date instructions to build the mobile apps are in the [Ente Photos](https://github.com/ente/ente/tree/main/mobile#readme) and [Ente Auth](https://github.com/ente/ente/tree/main/auth#readme) READMEs. When building or running, you can use the

```sh
--dart-define=endpoint=http://localhost:8080
```

parameter to get these builds to connect to your custom self-hosted server.

As a short summary, you can install Flutter and build the Photos app this way:

```sh
cd ente/mobile
flutter pub get
# Android
flutter run --dart-define=endpoint=http://localhost:8080 --flavor independent --debug -t lib/main.dart
# iOS
flutter run --dart-define=endpoint=http://localhost:8080
```

Or for the auth app:

```sh
cd ente/auth
git submodule update --init --recursive
flutter pub get
flutter run --dart-define=endpoint=http://localhost:8080
# Android
flutter run --dart-define=endpoint=http://localhost:8080 --flavor independent --debug -t lib/main.dart
# iOS
flutter run --dart-define=endpoint=http://localhost:8080
```

## How to build non-debug builds

For building APK, [setup your keystore](https://docs.flutter.dev/deployment/android#create-an-upload-keystore) and run

```sh
flutter build apk --release --flavor independent -t lib/main.dart
```
