# Configurable Self-Hosted Mobile Build Guide

Start at the [self-hosted mobile documentation index](SELF_HOSTED_DOCUMENTATION.md)
if you need to choose between building, distributing, or testing an existing
release. This guide is the canonical command reference for operators and
maintainers who build and audit the applications; it does not contain tester
invitations or deployment-specific secrets.

This guide builds the personal Ente Photos Android and iOS applications for
a default Museum HTTPS origin. The applications can later validate and switch
to another HTTPS Museum origin through their guarded Server Settings page.
For closed-beta Android release, tester, update, and recovery procedures, use
the [Android distribution operations guide](SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md).
For the corresponding Apple Ad Hoc and Firebase workflow, use the
[iOS distribution operations guide](SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md).

The personal applications use separate identities from the official Ente app:

- Android release package: `me.vanton.ente.photos.selfhosted`
- Android debug package: `me.vanton.ente.photos.selfhosted.debug`
- iOS bundle identifier: `me.vanton.ente.photos.selfhosted`

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

## 2. Toolchain variables

The project and CI use Flutter 3.38.10. The 2026-07-20 upstream integration was
verified with its bundled Dart 3.10.9, rustup-managed Rust/Cargo 1.97,
CocoaPods 1.17.0, and JDK 17. Keep personal toolchains outside the repository
and adapt the private root below to the installation on the build Mac:

```sh
export ENTE_MOBILE_TOOLCHAIN_ROOT="$HOME/.local/share/ente-mobile-toolchain"
export FLUTTER_BIN="$ENTE_MOBILE_TOOLCHAIN_ROOT/flutter-3.38.10/bin/flutter"
export DART_BIN="$ENTE_MOBILE_TOOLCHAIN_ROOT/flutter-3.38.10/bin/dart"

export JAVA_HOME="$ENTE_MOBILE_TOOLCHAIN_ROOT/jdk-17/Contents/Home"
export ANDROID_HOME="$ENTE_MOBILE_TOOLCHAIN_ROOT/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="$HOME/.cargo/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$(dirname "$FLUTTER_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
```

`FLUTTER_BIN` and `DART_BIN` may instead point to another private, pinned
Flutter 3.38.10 installation. Do not commit the private toolchain root.

From the repository root, install the lockfile-pinned Flutter dependencies when
needed:

```sh
cd mobile
"$FLUTTER_BIN" pub get --enforce-lockfile
cd apps/photos
```

Put rustup's `cargo` and `rustc` before incompatible Homebrew installations on
`PATH`, as shown above. The Android application currently compiles and targets
API 36, supports API 26 and later, and pins NDK `28.2.13676358`. A newer Java
runtime may start Gradle but still cannot satisfy a plugin's Java 17 toolchain;
use JDK 17 for the complete Android build.

For iOS dependency regeneration, use the CocoaPods version recorded at the end
of `ios/Podfile.lock` (currently 1.17.0):

```sh
cd ios
pod install --deployment
cd ..
```

The self-hosted iOS target and its pods require iOS 15.1 or later.

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

The personal signing material is stored outside Git:

```text
$ENTE_MOBILE_TOOLCHAIN_ROOT/signing/ente-photos-selfhosted-release.jks
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

#### Audited release preparation

Use the release-preparation command for any APK intended for distribution. It
requires a clean committed and pushed worktree, delegates the build to the
guarded configurable wrapper, deletes the expected build output first so a
stale APK cannot pass, and audits the final binary rather than trusting build
arguments.

Choose an absolute output directory outside the Git repository. Prepared files
are never overwritten and are made read-only:

```sh
./scripts/prepare_self_hosted_android_release.sh \
  --output-dir "$ENTE_MOBILE_TOOLCHAIN_ROOT/prepared-releases"
```

The command verifies:

- The source worktree is clean, remains on one commit throughout the build,
  and that commit is reachable from an `origin/*` ref.
- `origin` produces an exact GitHub commit URL for the corresponding AGPL source.
- The APK package and pubspec version match the reviewed source.
- The APK is non-debuggable and uses the pinned SDK range and ARM ABIs.
- The complete canonical HTTPS origin exists in the compiled Flutter library.
- ZIP integrity, APK Signature Scheme v2, the one expected signer certificate,
  and the final SHA-256 all pass.

Success writes an immutable-name APK and adjacent `.manifest.json`. The JSON
records the absolute artifact path and hash, source commit and URL, Android
identity and version, SDKs, ABIs, endpoint, signature schemes, signer
fingerprint, and preparation schema/tool version. Signing passwords and other
credentials are neither printed nor written to the manifest.

This preparation stage does not invoke Firebase or upload anything. Publication
must consume the exact APK and manifest produced here; it must not rebuild or
resign the application.

#### Guarded Firebase publication

Use the publication command only with a manifest produced by the preparation
command above. Supply the Firebase project and Android App ID locally so this
public repository is not bound to one operator's Firebase project. The target
App Distribution group is fixed to `trusted-testers`.
The end-to-end operational checklist is in the
[Android distribution operations guide](SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md).

First run the read-only preflight. Use absolute paths outside this Git
repository for both the prepared manifest and publication receipts:

```sh
export FIREBASE_CLI="/absolute/path/to/firebase"

./scripts/publish_self_hosted_android_release.sh \
  --manifest "/absolute/path/prepared-releases/RELEASE.manifest.json" \
  --receipt-dir "/absolute/path/firebase-receipts" \
  --firebase-project "YOUR_FIREBASE_PROJECT_ID" \
  --firebase-app "YOUR_FIREBASE_ANDROID_APP_ID" \
  --preflight-only
```

The preflight re-hashes and independently inspects the APK, checks every pinned
manifest field, verifies the exact active Firebase Android package and
`trusted-testers` group, and checks prior guarded receipts for a non-increasing
version code. It performs no upload and creates no receipt.

To publish the same release, run the command again without
`--preflight-only`. Review the complete summary and type the displayed
`PUBLISH <release-id>` confirmation exactly. The command repeats the file and
Firebase checks after confirmation, then invokes only Firebase App Distribution
with the prepared APK, generated release notes, and the fixed group. It never
invokes Flutter, Gradle, the preparation command, or the keystore.

Generated release notes include the package version, APK SHA-256, exact AGPL
source commit URL, and commit-pinned build instructions. Optional operator
notes can be appended from an absolute path:

```sh
  --release-notes-file "/absolute/path/release-notes.txt"
```

A successful publication writes a read-only
`<release-id>.firebase-release.json` outside Git. It preserves the Firebase
console, tester, and temporary binary-download references and becomes the local
version ledger for later updates. It is never overwritten. If Firebase fails
after the upload starts, the command instead preserves a read-only
`.firebase-attempt-*.json` recovery record and requires the operator to inspect
Firebase before retrying.

For an exit-`0` JSON-only attempt that omitted release references, never upload
again. Save an immutable response from Firebase's official read-only
`projects.apps.releases.list` API in a private external directory, then set:

```sh
export ENTE_FIREBASE_ANDROID_ATTEMPT="/absolute/private/path/firebase-attempt.json"
export ENTE_FIREBASE_ANDROID_RELEASE_EVIDENCE="/absolute/private/path/firebase-release-list.json"
```

Run the same publisher first with `--preflight-only`, then without it. This
mode re-audits the APK and Firebase bindings, requires one exact official
app/version/build/notes/time/reference match, and writes the normal immutable
success receipt with evidence hashes and `noUploadPerformed: true`. It does not
prompt, upload, notify testers, or delete either evidence file. Normal future
publications request the reference-bearing Firebase CLI output directly.

Use a locally authenticated Firebase CLI session. Legacy `FIREBASE_TOKEN`,
Google credential-file variables, and Android signing/password variables are
removed from every inspection and Firebase subprocess.

Install it on a connected USB-debugging device:

```sh
adb install -r build/app/outputs/flutter-apk/app-selfhosted-release.apk
```

The earlier locked release artifact built for the original local endpoint may
be retained in the operator's private artifact archive as historical rollback
evidence. It is not a current distribution artifact.

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
xcrun simctl launch booted me.vanton.ente.photos.selfhosted
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
  me.vanton.ente.photos.selfhosted
```

An unpaid Personal Team produces a short-lived provisioning profile. Rebuild
and reinstall the application when that profile expires; signing through a
separate self-hosted bundle identifier does not replace the official Ente app.

Use `--no-codesign` only when a non-installable device artifact is explicitly
needed for later signing.

### Manually signed Ad Hoc archive and IPA

Use the same guarded wrapper to produce the distributable Ad Hoc archive and
IPA. This path is separate from the automatic development signing above: it
requires the exact local distribution team and owner-only Ad Hoc profile, pins
the reviewed distribution certificate, and uses manual signing throughout.

Keep the provisioning profile and all outputs outside Git. Create only their
parent directories; the archive and export paths themselves must not exist
because the wrapper never overwrites release output. Choose a new positive
build number for every changed IPA. The version values below are examples;
Task 1.8 selects and audits the actual baseline values.

```sh
export ENTE_IOS_DISTRIBUTION_TEAM="YOURTEAMID"
export ENTE_IOS_ADHOC_PROFILE="/absolute/private/path/Ente_Photos_SelfHosted_Owner_Ad_Hoc.mobileprovision"
export ENTE_IOS_EXPECTED_DEVICE_COUNT="1"
export ENTE_IOS_MARKETING_VERSION="1.0.0"
export ENTE_IOS_BUILD_NUMBER="1"
export ENTE_IOS_ARCHIVE_PATH="/absolute/private/path/outputs/Ente-Photos-SelfHosted-1.xcarchive"
export ENTE_IOS_EXPORT_PATH="/absolute/private/path/outputs/Ente-Photos-SelfHosted-1-ipa"
```

Replace `YOURTEAMID` locally with the ten-character Apple Team ID. Do not add
that value, the profile, or any device identifier to Git. Both output parents
must already exist and be writable, and every path must resolve outside the
repository.

First validate the complete signing and output contract without invoking
Flutter or Xcode or creating an archive/IPA:

```sh
./scripts/build_self_hosted_ios.sh --adhoc-preflight
```

The preflight decodes the profile and verifies its exact bundle and team,
non-debug Ad Hoc state, authorized-device count, expiry, single embedded
certificate, pinned certificate fingerprint and validity, and matching local
Keychain private-key identity. A validated profile is installed into Xcode's
local provisioning-profile cache with restrictive permissions.

Then create the archive and IPA using the same unchanged environment:

```sh
./scripts/build_self_hosted_ios.sh --adhoc
```

The command configures the `selfhosted` Flutter release with the configurable
endpoint defines and explicit version/build, archives `SelfHostedRunner` with
manual signing, and generates a temporary Xcode export-options file. On the
pinned Xcode 26 toolchain, Ad Hoc export uses the current `release-testing`
method. The wrapper never enables Xcode's provisioning-update or
device-registration flags and requires exactly one exported `.ipa` beneath
`ENTE_IOS_EXPORT_PATH`.

The resulting `.xcarchive` and IPA are private local artifacts. Task 1.8 audits
their final contents before either is treated as a baseline release.

### Prepare an immutable audited IPA

Use the preparation command for every IPA that may later be published. Unlike
the lower-level Ad Hoc command, it owns temporary archive/export paths, builds
from a detached worktree at the pushed `HEAD` commit, resolves the committed
Flutter lockfile, and regenerates every ignored compile-time source there. The
generation order is shared and Photos localizations, the repository's official
`cargo codegen frb` command, then narrowly filtered shared and Photos builders
for the required ignored Rust APIs and tracked Photos model outputs. The latter
must remain byte-identical so the checkout stays clean. Preparation requires all
FRB files, both ignored Freezed files, both localization entrypoints, and every
locale file those entrypoints import before independently auditing the exported
IPA and atomically preserving one read-only IPA/JSON manifest pair. The
generators see
only required toolchain/cache paths—not endpoint, Apple-signing, Firebase,
Google Cloud, SSH-agent, or general secret variables. Preparation never
contacts Firebase.

Commit and push the preparation tooling and every intended application change
before running it. The command refuses an unpushed `HEAD` and refuses when its
critical build/preparation scripts differ from that pushed commit. Unrelated
working-tree changes are isolated from the release checkout.

Set the same endpoint, signing, device-count, and version inputs used by the
Ad Hoc build. Do not set archive or export paths; preparation creates and
removes those temporary paths itself. Choose an existing writable output
directory outside the repository. Preparation restricts that directory to
mode `0700` because each IPA embeds its private authorized-device list:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://museum.example"
export ENTE_IOS_DISTRIBUTION_TEAM="YOURTEAMID"
export ENTE_IOS_ADHOC_PROFILE="/absolute/private/path/Ente_Photos_SelfHosted_Owner_Ad_Hoc.mobileprovision"
export ENTE_IOS_EXPECTED_DEVICE_COUNT="1"
export ENTE_IOS_MARKETING_VERSION="1.0.0"
export ENTE_IOS_BUILD_NUMBER="1"

./scripts/prepare_self_hosted_ios_release.sh \
  --output-dir "/absolute/private/path/prepared-releases"
```

The marketing version must match the selected commit's `pubspec.yaml`; every
changed IPA must use a new positive build number. Keep the Team ID, profile,
device identifiers, archives, IPAs, and manifests outside Git.

Before finalization, the command checks the ZIP structure, exact self-hosted
bundle/version, compiled HTTPS endpoint, absence of extensions and debug
entitlements, application/team identity, device-scoped profile and authorized
device count, pinned and currently valid signing certificate, code-signature
structure, and arm64 architecture of every Mach-O file. The manifest records
the pushed source URL/commit, clean-checkout evidence, audit results, artifact
size, and SHA-256 without recording device identifiers.

Successful output is named from the version, build, and source commit. The IPA
and manifest are mode `0444`, are finalized without overwrite, and must remain
together. A later Firebase publisher consumes this immutable pair; do not
rename, edit, replace, or manually publish either file.

### Preflight and publish an immutable IPA through Firebase

The guarded publisher consumes only the preparation manifest. It never invokes
Flutter, Xcode, archive/export, signing, provisioning-profile changes, or Apple
account operations. Keep the Firebase project/App ID binding and receipt
ledger outside Git; the receipt directory is restricted to mode `0700`.

Set the private local binding and the exact prepared manifest, then run the
non-mutating preflight first:

```sh
export ENTE_IOS_RELEASE_MANIFEST="/absolute/private/path/prepared-releases/ente-photos-selfhosted-ios-1.0.0-1-0123456789ab.manifest.json"
export ENTE_FIREBASE_RELEASE_RECEIPT_DIR="/absolute/private/path/firebase-receipts"
export ENTE_FIREBASE_PROJECT_ID="your-private-project-id"
export ENTE_FIREBASE_IOS_APP_ID="your-private-ios-app-id"

./scripts/publish_self_hosted_ios_release.sh --preflight-only
```

The preflight re-hashes the read-only IPA/manifest pair, repeats the native IPA
audit, validates the exact active Firebase iOS bundle registration and pinned
`trusted-ios-testers` group, checks prior success receipts, and generates the
AGPL source/build links used in release notes. It also requires manifest proof
that Rust bindings and their compile-critical Dart sources were generated
inside the isolated source checkout. It neither prompts nor uploads.

Optional operator-facing notes can be added from a regular local text file:

```sh
./scripts/publish_self_hosted_ios_release.sh \
  --release-notes-file "/absolute/private/path/release-notes.txt"
```

Without `--preflight-only`, the command prints the complete target summary and
requires typing `PUBLISH <release-id>` exactly. After confirmation it re-reads
and re-audits both files, repeats the increasing-build ledger check, and
re-queries Firebase immediately before its single mutating distribute call.
It passes only the exact iOS App ID, `trusted-ios-testers`, and generated notes
file to Firebase; there is no free-form tester target.

Success writes one collision-safe mode-`0444` receipt. A Firebase failure—or a
zero exit that omits unambiguous release references—writes a distinct
mode-`0444` partial-attempt record because an upload may already have occurred.
Inspect the Firebase console and reconcile that record before retrying; never
assume a CLI error means Firebase is unchanged. Only successful receipts enter
the version ledger, and every later publication for this bundle/App ID must
have a strictly higher `CFBundleVersion`.

If Firebase returns JSON-only success, do not upload again. Use an approved
authenticated client to save the official read-only
[`projects.apps.releases.list`](https://firebase.google.com/docs/reference/app-distribution/rest/v1/projects.apps.releases/list)
response in a mode-`0700` private directory, make the response mode `0444`, and
reconcile the immutable attempt/evidence pair:

```sh
export ENTE_FIREBASE_IOS_ATTEMPT="/absolute/private/path/firebase-ios-attempt.json"
export ENTE_FIREBASE_IOS_RELEASE_EVIDENCE="/absolute/private/path/firebase-release-list.json"

./scripts/publish_self_hosted_ios_release.sh --preflight-only
./scripts/publish_self_hosted_ios_release.sh
```

Reconciliation re-audits the IPA, rechecks the active Firebase app/group, and
requires the attempt's exit-`0` JSON success to match exactly one official
release by app resource, version/build, release notes, creation window, and all
three Firebase references. The first command writes nothing; the second writes
the normal immutable success receipt without prompting, uploading, notifying,
or deleting the preserved attempt/evidence files. Normal future publications
request Firebase CLI output containing those references directly.

For Apple device registration, Ad Hoc profile refresh, Firebase tester
onboarding, Developer Mode, Tailscale access, updates, offboarding, and
recovery, follow the
[iOS distribution operations guide](SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md).

## 5. Server defaults, upgrades, and switching

`ENTE_SELF_HOSTED_ENDPOINT` becomes the clean-install default. Once the app has
a valid stored server binding, that binding wins over defaults supplied by
later builds. Consequently:

- Installing a later configurable build with the same application identity
  preserves its server binding, account, and photos. This applies to future
  Android and iOS builds using `me.vanton.ente.photos.selfhosted` within their
  respective platforms.
- The earlier Android package `com.vanton1.ente.photos.selfhosted` is a separate
  application. Moving to the renamed Android package is a clean install and
  does not migrate its app-local binding, account, keys, or queued work. Sync
  important work first, then log in and download the cloud library again.
- The earlier iOS bundle `com.vanton1.ente.photos.selfhosted` is likewise
  unrelated to `me.vanton.ente.photos.selfhosted`. Keep both installed while
  validating the renamed app, then remove the old app only after cloud recovery
  and sign-in have been proven; no app-local state migrates between them.
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
