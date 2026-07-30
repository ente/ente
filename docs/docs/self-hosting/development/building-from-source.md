---
title: Building Ente from source
description: From a blank machine to every Ente app running locally
---

# Building Ente from source

Everything Ente makes lives in one git repository: the Photos app (on mobile, web, and desktop), Auth, Locker, the server that backs them, a CLI, and the shared Rust underneath.

That is four languages, Rust, TypeScript, Go, and Dart, which sounds like a lot. But we take great care to stick to very standard setups for each of those languages. If you have ever run `cargo`, `npm`, `go`, or `flutter`, you already know how to build the part of Ente that uses it. The whole job is installing those four toolchains and pointing the apps at a server running on your own machine.

This page walks all of it, blank machine to everything running.

## Scope

This page is not meant as an official guide. The canonical and up-to-date setup instructions are in each subdirectory's README.

Instead, my attempt here is to give a narrative tying all those READMEs together, and show how I configured a fresh macOS system from scratch. There are other ways to configure these things too; this is just what I happened to do.

The commands below are for macOS since macOS is needed for building the iOS app. However, they should mostly work on Linux or Windows too: the toolchains are identical; you only need to swap the package manager commands.

## Get the code

```sh
git clone https://github.com/ente/ente
cd ente
```

## Toolchains

Download [Xcode](https://apps.apple.com/app/xcode/id497799835) from the App Store.

> [!TIP]
>
> If you don't want to build the iOS app then the full Xcode is not needed, `xcode-select --install` is enough.

Install [brew](https://brew.sh).

Then the toolchains:

| Language | Install                                              | Used by              |
| -------- | ---------------------------------------------------- | -------------------- |
| Rust     | [rustup](https://www.rust-lang.org/tools/install)    | `rust/`, web, mobile |
| Node     | `brew install node`                                  | web, desktop, docs   |
| Go       | `brew install go`                                    | server, CLI          |
| Flutter  | [Docs](https://flutter.dev/docs/get-started/install) | mobile               |

Node and Go are one `brew` command each:

```sh
brew install node go
```

Rust uses [rustup](https://www.rust-lang.org/tools/install), its standard installer:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Flutter can be [installed](https://flutter.dev/docs/get-started/install) in many ways, none of them great. This is what I tend to do: download the zip, unzip it somewhere durable, and add its `bin` to `PATH`.

> [!NOTE]
>
> Unlike the other toolchains where any recent version would do, we pin fiddly Flutter to the [version CI uses](https://github.com/ente/ente/blob/main/.github/actions/setup-flutter/action.yml). At the time of writing, it was 3.38.10.

```sh
mkdir -p ~/.local/share
cd ~/.local/share
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.38.10-stable.zip
unzip -q flutter_macos_arm64_3.38.10-stable.zip

# Also added this to my ~/.zprofile
export PATH="$HOME/.local/share/flutter/bin:$PATH"
```

Then run `flutter doctor`. It'll tell us that Android is missing; we'll come to that in a bit.

> [!TIP]
>
> For updating Flutter to a different version,
>
> ```sh
> cd ~/.local/share/flutter
> git fetch origin --tags
> git switch --detach 3.38.10
> flutter --version
> flutter doctor
> ```

## Server

The server (we call it museum) is a single Go binary that wants a Postgres database and an S3-compatible object store beside it. On macOS, brew has both:

```sh
brew install postgresql@15 minio minio-mc
brew services run postgresql@15
brew services run minio
```

Create museum's database and a storage bucket, once:

```sh
psql postgres -c "CREATE USER pguser WITH PASSWORD 'pgpass'"
psql postgres -c "CREATE DATABASE ente_db OWNER pguser"
mc alias set local http://127.0.0.1:9000 minioadmin minioadmin
mc mb local/b2-eu-cen
```

Museum's defaults don't know about the database and bucket you just made, so create a `server/museum.yaml` pointing at them:

```yaml
db:
    host: localhost
    port: 5432
    name: ente_db
    user: pguser
    password: pgpass

s3:
    are_local_buckets: true
    b2-eu-cen:
        key: minioadmin
        secret: minioadmin
        endpoint: localhost:9000
        region: eu-central-2
        bucket: b2-eu-cen
```

Then start it:

```sh
cd server
go run cmd/museum/main.go
```

And verify it is responding:

```sh
curl http://localhost:8080/ping
```

A `pong` back means `localhost:8080` is ready to go!

> [!TIP]
>
> If you don't want to install Postgres and MinIO, then you can use Docker. The following will create a cluster running museum, DB and S3.
>
> ```sh
> cd server
> docker compose up --build
> ```
>
> See [server/RUNNING.md](https://github.com/ente/ente/blob/main/server/RUNNING.md) for more details.

## Web

```sh
cd web
npm ci
NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 npm run dev
```

That is the Photos app, with hot reload.

You can run other web apps the same way, e.g. `npm run dev:auth` and `npm run dev:albums`. See [web/README](https://github.com/ente/ente/tree/main/web#readme) for more details.

## Desktop

The Photos desktop app is the Photos web app wrapped in Electron, and builds on top of `web/`:

```sh
cd desktop
npm ci
npm run postinstall
NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 npm run dev
```

The Ensu desktop app is the Ensu web app wrapped in Tauri:

```sh
cd rust/apps/ensu
npm ci
npm run dev
```

> [!TIP]
>
> To quickly get back to the root of the repo,
>
> ```sh
> cd "$(git rev-parse --show-toplevel)"
> ```

## Mobile

The mobile apps (except Ensu) are Flutter, and all follow similar patterns, so I'll just describe how to get the Photos app to run.

> [!TIP]
>
> Reminder that the [README](https://github.com/ente/ente/tree/main/mobile/apps/photos#readme) is the source of truth for up-to-date instructions.

### iOS

Let us start with iOS. Install CocoaPods:

```sh
brew install cocoapods
```

Start a simulator:

```sh
open -a Simulator
```

Generate the Rust bindings:

```sh
cd rust
cargo codegen frb
```

Fetch the dependencies:

```sh
cd mobile
flutter pub get --enforce-lockfile
```

That's about it. Now we can run the Photos iOS app in the iOS Simulator, asking it to connect to our local museum:

```sh
cd mobile/apps/photos
flutter run --dart-define 'endpoint=http://localhost:8080'
```

### Android

The simple way is to install Android Studio. I did it the harder way, by installing the components that I need explicitly.

Install a JDK, symlinked where the toolchain looks for it:

```sh
brew install openjdk@17
sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk \
    /Library/Java/JavaVirtualMachines/openjdk-17.jdk
```

Install the Android Commandline Tools (as of writing we needed API 36):

```sh
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
```

The Android build compiles native code through the NDK, so install CMake:

```sh
brew install cmake
```

And an emulator to run on:

```sh
sdkmanager "emulator" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n pixel5-36 -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_5
```

Start an emulator, and forward ports to it so that it can communicate with the museum and S3 on localhost:

```sh
emulator -avd pixel5-36

adb reverse tcp:8080 tcp:8080
adb reverse tcp:9000 tcp:9000
```

Finally! now we can run the Android app on the emulator:

```sh
flutter run --flavor independent --dart-define 'endpoint=http://localhost:8080'
```

### Auth and Locker

The [Auth](https://github.com/ente/ente/tree/main/mobile/apps/auth#readme) and [Locker](https://github.com/ente/ente/tree/main/mobile/apps/locker#readme) follow the same pattern, though they might have some oddities that you'll find documented in the linked READMEs.

For example, for running the Ente Auth app in the iOS simulator, we need to also update the submodules to pull in icons.

```sh
git submodule update --init --recursive

cd mobile/apps/auth
flutter run --dart-define 'endpoint=http://localhost:8080'
```

### Ensu

Ensu mobile apps don't use Flutter, however, they are standard iOS/Android apps. The only non-standard thing is that before running them we first need to generate the Rust bindings:

```sh
cd rust
cargo codegen native
```

Then, for example, to run the Ensu Android app:

```sh
cd mobile/native/android/apps/ensu
./gradlew :app:installDebug
adb shell am start -n io.ente.ensu.debug/io.ente.ensu.MainActivity
```

Or, if you have Android Studio, you can just open `mobile/native/android/apps/ensu` and run. Same goes for opening `mobile/native/apple/apps/ensu` in Xcode and running.

## That's all folks.

That is the whole repository, every Ente app running from source on one machine.
