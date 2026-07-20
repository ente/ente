# Ente Photos Self-Hosted Tester Guide

Use this guide only after the operator invites you to the private Ente Photos
test group. This is a closed-beta, self-hosted application. It is separate from
the official Ente service and official Ente applications.

The operator will send these details to you privately:

- a Firebase App Distribution invitation;
- a Tailscale invitation or shared-machine link;
- the exact private Ente server address;
- the private Photos web-app address;
- instructions for creating or accessing your individual server account; and
- a support contact.

Do not post those details, invitation links, account credentials, recovery
keys, device identifiers, or screenshots containing personal information in a
public issue or chat.

## 1. Before you begin

- Use Android 8.0/API 26 or later, or iOS/iPadOS 15.1 or later. The operator
  must publish a build compatible with the exact device.
- Use your own Google account to accept Firebase. Keep using that same Google
  account for future downloads.
- Use your own identity for Tailscale and your own account on the private Ente
  server. These are three separate accounts.
- An account at `ente.com` is not automatically an account on this private
  server. Check the displayed server before entering credentials.
- Keep your account password, second-factor method, and recovery key somewhere
  safe outside the test device.
- Use only non-sensitive test photos until installation and synchronization are
  proven.

Android installation can normally begin as soon as the invitation is
accepted. iPhone and iPad installation has an additional registration step:
after registering the device, you must wait for the operator to publish a build
authorized for that exact device. A Mac cannot be used for this iOS device
registration or acceptance test.

## 2. Connect to the private network

Complete this section before opening Ente Photos:

1. Install the official Tailscale application from Google Play or Apple's App
   Store.
2. Sign in with your own Tailscale identity.
3. Accept the invitation or machine share sent by the operator.
4. Allow the Tailscale VPN configuration and connect it.
5. In the device's browser, open the private server address followed by
   `/ping`, for example:

   ```text
   https://private-server.example/ping
   ```

6. Continue only if the response says `pong`. If it does not, stop and contact
   the operator; reinstalling Ente Photos will not repair private-network
   access.

## 3. Android installation

1. Open the Firebase invitation on the Android device.
2. Sign in with the Google account you intend to keep using for this beta and
   accept the invitation. An invitation can be accepted only once.
3. Open [Firebase App Distribution](https://appdistribution.firebase.google.com)
   with that same Google account.
4. Select **Ente Photos Self-Hosted**, review the release information, and tap
   **Download**.
5. Follow Android's installation prompts. If Android asks for permission to
   install from the browser, confirm that the download came from Firebase
   before granting it. You may turn that permission off again after the
   installation.
6. Open **Ente Photos Self-Hosted**. The official Ente application can remain
   installed; this beta uses a separate application identity.

Updates arrive through Firebase email and the Firebase tester page. Install a
new build over the existing beta. Do not uninstall first, because uninstalling
deletes the beta application's local state.

## 4. iPhone or iPad installation

### 4.1 Register the device

Perform these steps in Safari on the actual iPhone or iPad that will run the
application:

1. Open the Firebase invitation in **Safari**.
2. Sign in with the Google account you intend to keep using for this beta and
   accept the invitation. An invitation can be accepted only once.
3. On the application page, tap **Register device**.
4. Allow Firebase to download its configuration profile.
5. Open iOS or iPadOS **Settings**. Tap **Profile Downloaded**, or open
   **General > VPN & Device Management**, select the Firebase App Distribution
   profile, and install it.
6. Return to the Firebase App Distribution web clip and confirm that device
   registration completed.
7. Tell the operator only that registration is complete. Do not copy or send
   the device identifier and do not send a screenshot of the profile.

The Firebase profile registers the device and installs the Firebase tester web
clip. It does not authorize or install Ente Photos. The operator must privately
register the device with Apple, add it to the application's provisioning
profile, build a higher-numbered release, and distribute that release.

### 4.2 Wait for the compatible build

Do not repeatedly download an older build after registration. Wait until the
operator confirms that a new build includes your device and Firebase sends its
release notification.

Then:

1. Open the Firebase App Distribution web clip using the same Google account.
2. Select **Ente Photos Self-Hosted** and tap **Download**.
3. If iOS reports that Developer Mode is required, open **Settings > Privacy &
   Security > Developer Mode**, enable it, restart the device, unlock it, and
   confirm **Turn On** with the device passcode.
4. Launch **Ente Photos Self-Hosted**.

Later updates also arrive through Firebase. Install them over the current beta
instead of deleting the application first.

## 5. Confirm the server before signing in

The first screen should show the private server address supplied by the
operator. Compare the scheme and hostname exactly.

- If the address is correct, continue to sign-in or account creation.
- If it is wrong, open **Server Settings**, enter the exact HTTPS server
  address, validate it, and switch before signing in.
- If you are already signed in, changing the server requires a confirmed local
  logout. This clears only this installation's local account state; it does not
  delete encrypted server data.
- If the application says the server cannot be verified, stop. Do not replace
  HTTPS with HTTP, use a raw IP address, or bypass certificate warnings. Send
  the error text to the operator.

Sign in with your individual account on the private Ente server, not your
Firebase or Tailscale credentials. Do not use the operator's Ente account.

## 6. Basic acceptance test

After signing in:

1. Confirm the app still shows the intended private server and note the release
   version and build number.
2. Upload one non-sensitive test photo while the app is open.
3. Wait until the upload reports that it is backed up or synchronized.
4. Open the private Photos web application and confirm the photo appears in
   your own account.
5. Upload a different non-sensitive test image through the web application.
6. Confirm that image synchronizes to the mobile application and can be opened
   or downloaded.
7. Force-close and reopen the mobile application.
8. Confirm that you remain signed in to the same server and that both cloud
   items remain readable.
9. Report success privately to the operator.

Do not use irreplaceable media for this test. Removing an item from Ente can
remove its cloud copy; deleting only the phone's local camera copy is a
different action.

## 7. Troubleshooting

| Problem | What to do |
|---|---|
| The invitation is invalid or already used | Ask the operator to check your tester status or resend the invitation. Keep using the intended Google account. |
| The application is missing from Firebase | Confirm that Firebase is signed in with the same Google account that accepted the invitation. |
| The `/ping` address does not return `pong` | Connect Tailscale and confirm that its invitation or machine share was accepted. Contact the operator if it still fails. |
| The server cannot be verified | Confirm the exact HTTPS hostname supplied by the operator. Do not use HTTP, a raw IP address, or ignore a certificate warning. |
| Android blocks the APK installation | Confirm the download came from Firebase, then follow Android's per-browser installation-permission prompt. |
| iOS says the device is registered but no build can be installed | Wait for the operator to publish a new build whose Apple provisioning profile contains your device. |
| iOS reports “Unable to Install” or an integrity error | Stop and contact the operator. The build may not include the exact device or may have expired signing authorization. |
| iOS requires Developer Mode | Enable it under **Settings > Privacy & Security**, restart, unlock, and confirm it with the device passcode. |
| Login opens the wrong account or service | Check the server shown by the app. Complete local logout before switching to the private server. |
| `/ping` works but uploads or downloads fail | Keep the app open and report the exact error. The operator must check the separate object-storage route. |

When reporting a problem, include the platform, OS version, app version/build,
the step that failed, and the exact error text. Do not include passwords,
verification codes, recovery keys, invitation URLs, device identifiers, or
personal photo names.

## 8. Leaving the test

Tell the operator when you want to leave. The operator must remove Firebase
delivery, private-network access, and private-server access separately. You can
then uninstall the beta and remove or sign out of Tailscale if you no longer
use it.

Do not delete the private Ente account or encrypted cloud library unless you
and the operator explicitly agree on the data-retention result.

## 9. Official help

These steps were checked on 2026-07-20 against:

- [Firebase tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester)
- [Firebase registration of additional Apple devices](https://firebase.google.com/docs/app-distribution/register-additional-devices)
- [Tailscale for Android](https://tailscale.com/docs/install/android)
- [Tailscale for iOS](https://tailscale.com/docs/install/ios)
- [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
