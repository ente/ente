# Self-Hosted Android Closed-Beta Operations

Start at the [self-hosted mobile documentation index](SELF_HOSTED_DOCUMENTATION.md)
for document ownership and current release state. This runbook is for the
operator. Send testers the separate
[Android and iOS onboarding guide](SELF_HOSTED_TESTER_ONBOARDING_GUIDE.md),
which contains no operator-only values.

This is the operator runbook for distributing the configurable Ente Photos
Android application to the private `trusted-testers` group through Firebase
App Distribution. It covers release preparation, publication, tester access,
updates, removal, and recovery. For toolchain and signing setup, use the
[mobile build guide](SELF_HOSTED_BUILD_GUIDE.md).

The workflow distributes only the Android package
`me.vanton.ente.photos.selfhosted`. It does not add a Firebase runtime SDK,
publish the application through Google Play, expose the private server to the
internet, or distribute the iOS application.

**Verified baseline (2026-07-20):** source version `1.3.59+2159`; Firebase
Android build `2159`; owner and non-owner installation, sign-in,
upload/download, and persistence accepted. Every later Android publication
must use a strictly higher version code. Current source requires Android
8.0/API 26 or later and targets API 36.

## 1. Trust boundaries and safety rules

Three independent systems grant different kinds of access:

| System | Grants | Does not grant |
|---|---|---|
| Firebase App Distribution | Invitation, APK download, and update delivery | Tailscale connectivity or a Museum account |
| Tailscale | Private network access to Museum and object storage | Firebase release access or Museum authentication |
| Museum | An individual encrypted-data account and server session | APK delivery or private network routing |

Onboard and offboard each tester in all applicable systems. Removing a tester
from Firebase does not uninstall an APK. Removing only Tailscale access does not
remove the Firebase invitation or Museum account.

Always follow these rules:

- Keep tester email addresses, Firebase or Tailscale invite links, access
  tokens, server credentials, account recovery material, and signing passwords
  out of Git, release notes, issue trackers, and screenshots committed to the
  repository.
- Treat a Tailscale invite link like a password. Coordinate identities through
  a private channel and verify the identity that accepted each invitation.
- Give every person their own Google, Tailscale, and Museum identity. Do not
  share the owner's accounts.
- Never run `firebase login:list --json`; Firebase CLI `15.24.0` exposed reusable
  OAuth material through that command during initial provisioning. Verify CLI
  access with a harmless resource query instead.
- Never publish from a dirty or unpushed source commit. Never edit, replace, or
  make a prepared APK or manifest writable.
- Do not use Firebase's temporary binary-download URL as a durable archive. It
  expires, while the local prepared APK, manifest, and publication receipt are
  the release evidence.

## 2. Private operator inputs

Set these values locally. The examples are placeholders, not configuration to
commit:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://museum-host.tailnet-name.ts.net"
export ENTE_OBJECT_STORAGE_HEALTH_URL="https://museum-host.tailnet-name.ts.net:8443/minio/health/live"
export ENTE_SERVER_DIR="/absolute/path/to/private/quickstart"

export FIREBASE_CLI="/absolute/path/to/firebase"
export ENTE_FIREBASE_PROJECT_ID="your-firebase-project-id"
export ENTE_FIREBASE_ANDROID_APP_ID="your-firebase-android-app-id"

export ENTE_ANDROID_RELEASE_OUTPUT_DIR="/absolute/path/to/prepared-releases"
export ENTE_FIREBASE_RELEASE_RECEIPT_DIR="/absolute/path/to/firebase-receipts"
```

The server directory, release directories, and Firebase credentials stay
outside this repository. The Firebase project and App ID are not secrets, but
keeping them local prevents the public fork from becoming operationally bound
to one Firebase project.

Confirm the CLI can see the intended project without printing authentication
state:

```sh
"$FIREBASE_CLI" projects:list
"$FIREBASE_CLI" appdistribution:groups:list \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

The second command must show the stable alias `trusted-testers`.

## 3. Prepare and publish one release

### 3.1 Check the server before building

Do not publish an application update to compensate for a server outage. From
the private quickstart directory, confirm the containers are running:

```sh
cd "$ENTE_SERVER_DIR"
docker compose ps
```

From a Tailscale-connected client, verify Museum's public health contract:

```sh
curl --fail --silent --show-error "$ENTE_SELF_HOSTED_ENDPOINT/ping"
```

The response must be successful JSON whose `message` is `pong`. Verify the
object-storage route separately because Museum returns signed upload and
download URLs for that origin:

```sh
curl --fail --silent --show-error "$ENTE_OBJECT_STORAGE_HEALTH_URL"
```

Also confirm that the HTTPS certificate is trusted and that the private
hostname resolves on the target network. A reachable Tailscale address with an
HTTP `502` from `/ping` points to the server or proxy layer, not an app build.

### 3.2 Prepare the immutable release

From `mobile/apps/photos`, confirm that the intended source is committed,
pushed to the fork, and reachable through `origin`:

```sh
git status --short
git branch -r --contains HEAD
```

The first command must print nothing. The second must include an `origin/*`
reference. Configure release signing as described in the build guide, then run:

```sh
./scripts/prepare_self_hosted_android_release.sh \
  --output-dir "$ENTE_ANDROID_RELEASE_OUTPUT_DIR"
```

Copy the exact manifest path printed by the command. Do not select a manifest
through a `latest` symlink or a wildcard:

```sh
export ENTE_ANDROID_RELEASE_MANIFEST="/absolute/path/to/the-printed-release.manifest.json"
```

Review the adjacent read-only APK and JSON manifest. Confirm at least:

- package `me.vanton.ente.photos.selfhosted`;
- intended version name and increasing version code;
- intended compiled HTTPS Museum origin;
- source commit and public fork commit URL;
- expected signing-certificate SHA-256;
- APK SHA-256 and read-only paths outside Git.

### 3.3 Run the non-mutating publication preflight

```sh
./scripts/publish_self_hosted_android_release.sh \
  --manifest "$ENTE_ANDROID_RELEASE_MANIFEST" \
  --receipt-dir "$ENTE_FIREBASE_RELEASE_RECEIPT_DIR" \
  --firebase-project "$ENTE_FIREBASE_PROJECT_ID" \
  --firebase-app "$ENTE_FIREBASE_ANDROID_APP_ID" \
  --preflight-only
```

The command must end with `Preflight passed. No Firebase upload was performed.`
It re-audits the exact APK, checks prior guarded receipts for a non-increasing
version, and verifies the active Firebase package and `trusted-testers` group.

### 3.4 Add or review testers

Prefer the Firebase console's **App Distribution > Testers & Groups** page when
handling human identities. Add the intended people to `trusted-testers` and
verify the group contains no unexpected identities. Do not put the list in a
repository file.

The equivalent CLI command is available when appropriate for the operator's
local shell:

```sh
"$FIREBASE_CLI" appdistribution:testers:add "<tester-email>" \
  --group-alias trusted-testers \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

Firebase sends a first-time tester an invitation. At the time this runbook was
verified, an unaccepted invitation expires after 30 days and can be renewed
from the tester row in the console. Recheck the official retention reference
in section 8 if timing affects an operation.

### 3.5 Publish the audited bytes

Optional operator-visible notes belong in a local text file. Do not include
secrets, tester identities, private invitation links, or recovery material.
The command generates the version, APK hash, exact AGPL source commit, and
commit-pinned build-instructions link automatically.

Run the same command without `--preflight-only`:

```sh
./scripts/publish_self_hosted_android_release.sh \
  --manifest "$ENTE_ANDROID_RELEASE_MANIFEST" \
  --receipt-dir "$ENTE_FIREBASE_RELEASE_RECEIPT_DIR" \
  --firebase-project "$ENTE_FIREBASE_PROJECT_ID" \
  --firebase-app "$ENTE_FIREBASE_ANDROID_APP_ID"
```

Review every summary field. Type the displayed `PUBLISH <release-id>` value
exactly only when the APK, source, server, Firebase app, and group are correct.
The command rechecks the files and Firebase registration after confirmation,
uploads the unchanged APK, and writes a read-only
`<release-id>.firebase-release.json` receipt outside Git.

### 3.6 Reconcile Firebase and the receipt

After success:

1. Open the receipt's Firebase console URL and confirm the displayed version,
   build number, release notes, and `trusted-testers` distribution.
2. Confirm the release notes contain the exact public source commit URL.
3. Confirm the receipt's APK SHA-256 matches the prepared manifest.
4. Confirm the Firebase console shows the intended testers as invited or
   accepted; later, confirm download status for device acceptance tests.
5. Preserve the prepared APK, manifest, and receipt together outside Git.

If the command writes `.firebase-attempt-*.json`, Firebase may have accepted the
binary before a later step failed. Inspect the attempt record and Firebase
console before any retry. Do not assume a nonzero exit means no mutation.

If the attempt records exit-`0` JSON success but lacks the three release
references required by the receipt, do not upload again. Use an approved
authenticated client to save the official read-only
[`projects.apps.releases.list`](https://firebase.google.com/docs/reference/app-distribution/rest/v1/projects.apps.releases/list)
response in a private mode-`0700` directory, then make the response mode
`0444`. Set both immutable inputs locally:

```sh
export ENTE_FIREBASE_ANDROID_ATTEMPT="/absolute/private/path/firebase-attempt.json"
export ENTE_FIREBASE_ANDROID_RELEASE_EVIDENCE="/absolute/private/path/firebase-release-list.json"
```

Run a no-write reconciliation preflight, then finalize the receipt from the
same inputs:

```sh
./scripts/publish_self_hosted_android_release.sh --preflight-only
./scripts/publish_self_hosted_android_release.sh
```

Reconciliation re-audits the APK, rechecks the active Firebase app/group and
version ledger, and requires exactly one official release matching the app
resource, version/build, immutable notes, attempt time window, and all three
known-host references. It preserves and hashes the attempt and evidence,
writes the ordinary read-only success receipt with
`noUploadPerformed: true`, and cannot upload or notify testers. A mismatch or
ambiguous match writes nothing.

## 4. Onboard and accept a tester

The tester-facing sequence lives only in the
[shared onboarding guide](SELF_HOSTED_TESTER_ONBOARDING_GUIDE.md). The operator
completes this private handoff checklist:

1. Add the intended identity to Firebase group `trusted-testers` and verify
   there are no unexpected members.
2. Grant only the Tailscale host share or membership required by the deployment;
   do not enable a public Funnel for this beta.
3. Create or approve an individual Museum account according to the server's
   account policy. Never share the owner's account.
4. Send the Firebase invitation, required Tailscale instructions, exact Museum
   origin, and the shared tester guide through a private channel.
5. Privately verify the identity that accepted each invitation and require the
   guide's `/ping`, install, sign-in, upload/download, restart, and persistence
   acceptance result before declaring the release usable.

The application intentionally has no Firebase App Distribution runtime SDK.
Updates arrive through Firebase email and the tester web experience, not an
in-app update prompt. If an acceptance step fails, use section 7 and request
only the minimum redacted diagnostic information described in the tester guide.

## 5. First installation and later updates

### Application-ID cutover for the owner

The legacy package `com.vanton1.ente.photos.selfhosted` and the Firebase package
`me.vanton.ente.photos.selfhosted` are unrelated Android applications. Local
preferences, databases, cached keys, server binding, and sessions do not
migrate.

Before uninstalling the legacy package:

1. Confirm all intended media is backed up to Museum and can be downloaded.
2. Confirm the new Firebase release is visible and the private server is
   healthy.
3. Confirm the account password, second-factor method, and recovery material
   are available outside the device.
4. Accept that uninstalling discards the old package's app-local state.

Then uninstall the legacy package, install the Firebase release, and sign in to
the same Museum account. Encrypted cloud media remains associated with the
Museum account rather than the Android package.

### In-place Firebase updates

Every update must keep all of these stable:

- package `me.vanton.ente.photos.selfhosted`;
- signing certificate;
- intended private-server policy.

The Android version code must increase. Prepare and publish through section 3;
never upload a manually rebuilt APK. The tester opens the new Firebase build and
installs it over the existing package without uninstalling. Afterward, verify
that the account, server binding, and cloud media remain intact, then repeat one
controlled upload/download test.

## 6. Remove a tester

Offboarding is complete only after delivery, network, and server access are
handled.

1. In Firebase **Testers & Groups**, remove the person from
   `trusted-testers`. Firebase removes access to releases granted exclusively
   through that group. Check for access through any other group or individual
   release assignment.
2. If the person no longer needs any project release, remove the tester from the
   Firebase project as well.
3. Revoke the Tailscale machine share or remove/suspend the tailnet Member and
   their devices according to the existing tailnet policy.
4. Disable or remove the person's Museum account according to the server's
   account-retention policy. Do not delete encrypted server data without a
   separate explicit decision.
5. Record completion only in the private administrative system, not this
   repository.

CLI equivalents for the Firebase steps are:

```sh
"$FIREBASE_CLI" appdistribution:testers:remove "<tester-email>" \
  --group-alias trusted-testers \
  --project "$ENTE_FIREBASE_PROJECT_ID"

"$FIREBASE_CLI" appdistribution:testers:remove "<tester-email>" \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

An already installed APK can continue running. Firebase is a delivery control,
not a remote kill switch; private-server access must be revoked separately.

## 7. Recovery procedures

| Problem | Required response |
|---|---|
| Prepared APK or manifest changed | Stop. Discard the pair and prepare again from clean pushed source. Do not make it writable or repair it. |
| Wrong Firebase app, package, or group | Stop before confirmation. Correct the local inputs or registration; never upload to see whether Firebase accepts it. |
| Firebase failure after upload started | Preserve the partial attempt and inspect Firebase before any retry. For exit-`0` JSON-only success, capture immutable official release-list evidence and run guarded no-upload reconciliation; never upload the same release again. |
| Invitation expired | Resend the invitation from the Firebase tester row and privately confirm the intended Google identity. |
| Firebase release expired | Prepare the known-good source again with a higher Android version code and publish it through the guarded path. Do not bypass the receipt ledger by reusing the old code. |
| Bad application release | Select the last known-good public commit, increase its version code, prepare and publish it as a forward rollback, then repeat device acceptance. |
| Museum or MinIO unavailable | Restore Docker, proxy, Tailscale, DNS, and object-storage health. Do not publish an unchanged app for a server outage. |
| Tester cannot reach private host | Check Tailscale connection, accepted share/membership, approval state, full `*.ts.net` name, and access rules before changing the app. |
| Tester chose the wrong server | Complete local logout, select the correct server through Server Settings, then sign in to the correct Museum account. |
| Signing key unavailable or mismatched | Stop publishing. Existing installations cannot accept an update signed by a different certificate. Recover the original key or create a new package/Firebase app and perform another uninstall/reinstall cutover. |
| Firebase operator account compromised | Revoke the Firebase CLI session, rotate affected credentials, review project membership/releases/testers, and reauthenticate. Do not print login JSON while investigating. |

The current signing-key decision deliberately has no encrypted off-machine
keystore backup. Loss of the only key therefore means no in-place recovery: a
new signing identity and application ID are required, and every tester loses
that package's app-local state during reinstall. Museum-side encrypted media is
still recovered by signing in to the same server account.

## 8. Retention and primary references

These external rules were reverified on 2026-07-20 and can change:

- Firebase tester invitations expire after 30 days if unaccepted; the console
  warns shortly before expiry and can resend them.
- Firebase App Distribution releases are retained for 150 days and are also
  subject to a 1,000-release-per-app limit. Installed copies continue running
  after a release disappears from Firebase.
- Removing a tester from a Firebase group removes access to releases granted
  exclusively through that group; access through another group remains.
- Unused Tailscale user and machine-share invitations expire after 30 days.
- A Tailscale machine share is suitable for a fixed host; full tailnet
  membership is needed for broader resources such as subnet-router access.

Primary references:

- [Firebase Android CLI distribution](https://firebase.google.com/docs/app-distribution/android/distribute-cli)
- [Firebase tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester)
- [Firebase tester and group management](https://firebase.google.com/docs/app-distribution/add-remove-testers)
- [Firebase App Distribution retention and troubleshooting](https://firebase.google.com/docs/app-distribution/troubleshooting)
- [Tailscale: inviting users versus sharing a device](https://tailscale.com/docs/reference/inviting-vs-sharing)
- [Tailscale machine sharing](https://tailscale.com/docs/features/sharing)
- [Tailscale user invitations](https://tailscale.com/docs/features/sharing/how-to/invite-any-user)
- [Tailscale on Android](https://tailscale.com/docs/install/android)
