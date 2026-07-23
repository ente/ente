# Apple signing for CI

GitHub iOS builds are made using manual signing with the "-allowProvisioningUpdates" flag that makes xcodebuild pull any relevant provisioning profiles from the Apple Developer Portal.

- The builds are signed using a manually created Apple Distribution certificate that is supplied to the workflow as a secret.
- The provisioning profiles are fetched automatically, but they do need to be precreated (one per bundle ID).
- To fetch these, and for uploading the build, an App Store Connect API key needs to also be made available to the workflow.
- The Apple Distribution cert has a one year expiry, and needs to be manually recreated and updated in the secrets. The provisioning profiles are tied to a certificate, and so they also need to be recreated.

GitHub macOS builds are made by manually signing with an Apple Developer ID Application certificate and then notarized with Apple.

- The Apple Developer ID Application certificate is also provided to the workflow as a secret. It has a longer expiry too.
- For notarization, an Apple ID and an associated app-specific password are provided to the workflow.

## What you need

| Item                                   | Scope          | Notes                                                                                         |
| -------------------------------------- | -------------- | --------------------------------------------------------------------------------------------- |
| Developer ID Application certificate   | Team-wide      | `MAC_OS_CERTIFICATE`, `MAC_OS_CERTIFICATE_PASSWORD`                                           |
| Apple Distribution certificate         | Team-wide      | `APPLE_DISTRIBUTION_CERT_BASE64`, `APPLE_DISTRIBUTION_CERT_PASSWORD`                          |
| App Store Connect API key              | Team-wide      | `APP_STORE_CONNECT_API_KEY_BASE64`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` |
| Auth Developer ID provisioning profile | Auth macOS app | `AUTH_MACOS_DEVELOPER_ID_PROVISION_PROFILE_BASE64`                                            |
| App Store provisioning profile         | Per iOS app    | App Store profile downloaded by Xcode during the build                                        |

The Developer ID certificate and Apple Distribution certificate are different certificates. Developer ID is for distributing notarized macOS apps outside the Mac App Store. Apple Distribution is for App Store/TestFlight distribution.

On macOS, copy a file's base64 value for a GitHub secret with:

```sh
base64 -i path/to/file | pbcopy
```

## Team-wide setup

### Developer ID Application certificate

The macOS workflows sign desktop apps with a Developer ID Application certificate, then notarize the signed artifact with Apple.

Required GitHub secrets:

- `MAC_OS_CERTIFICATE`
- `MAC_OS_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_PASSWORD`
- `APPLE_TEAM_ID`

`MAC_OS_CERTIFICATE` is a base64-encoded `.p12` export containing the Developer ID Application certificate and its private key. The `.p12` password is stored in `MAC_OS_CERTIFICATE_PASSWORD`.

The notarization credentials are separate:

- `APPLE_ID` is the Apple ID used for notarization.
- `APPLE_PASSWORD` is an app-specific password for that Apple ID.
- `APPLE_TEAM_ID` is the 10-character Apple Developer team ID.

To create or rotate the Developer ID certificate:

1. Create a CSR in Keychain Access: Certificate Assistant > Request a Certificate from a Certificate Authority. Leave CA Email Address empty, choose Saved to disk.
2. In Apple Developer > Certificates, Identifiers & Profiles > Certificates, create a Developer ID Application certificate with that CSR.
3. Download the `.cer`, open it on the Mac that created the CSR, and export the certificate plus private key from Keychain Access as a password-protected `.p12`.
4. Set `MAC_OS_CERTIFICATE` to the base64 of that `.p12`.
5. Set `MAC_OS_CERTIFICATE_PASSWORD` to the `.p12` export password.

Keep old Developer ID certificates unless their private key is compromised or the certificate must no longer be trusted.

### Apple Distribution certificate

iOS workflows archive with manual signing and an imported Apple Distribution certificate. Use a normal local Apple Distribution certificate, not a cloud-managed certificate, because GitHub Actions imports the private key into the runner keychain.

Required GitHub secrets:

- `APPLE_DISTRIBUTION_CERT_BASE64`
- `APPLE_DISTRIBUTION_CERT_PASSWORD`
- `APPLE_TEAM_ID`

`APPLE_DISTRIBUTION_CERT_BASE64` is a base64-encoded `.p12` export containing the Apple Distribution certificate and its private key. The `.p12` password is stored in `APPLE_DISTRIBUTION_CERT_PASSWORD`.

To create or rotate the Apple Distribution certificate:

1. Create a CSR in Keychain Access: Certificate Assistant > Request a Certificate from a Certificate Authority. Leave CA Email Address empty, choose Saved to disk.
2. In Apple Developer > Certificates, Identifiers & Profiles > Certificates, create an Apple Distribution certificate with that CSR.
3. Download the `.cer`, open it on the Mac that created the CSR, and export the certificate plus private key from Keychain Access as a password-protected `.p12`.
4. Set `APPLE_DISTRIBUTION_CERT_BASE64` to the base64 of that `.p12`.
5. Set `APPLE_DISTRIBUTION_CERT_PASSWORD` to the `.p12` export password.
6. Regenerate every App Store provisioning profile that should use the new certificate.

### App Store Connect API key

iOS workflows use an App Store Connect API key for `xcodebuild -allowProvisioningUpdates` and TestFlight upload.

Required GitHub secrets:

- `APP_STORE_CONNECT_API_KEY_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Create the key in App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys. Use a team API key with App Manager access.

Download the `.p8` immediately; Apple only offers it once. Store:

- `APP_STORE_CONNECT_API_KEY_BASE64`: base64 of the `.p8`
- `APP_STORE_CONNECT_KEY_ID`: the 10-character key ID
- `APP_STORE_CONNECT_ISSUER_ID`: the issuer UUID

If the key is lost or compromised, revoke it and create a new one.

## Auth macOS setup

### Developer ID provisioning profile

Auth macOS builds use a Developer ID provisioning profile because Auth's macOS entitlements include keychain access groups. The profile is stored as `AUTH_MACOS_DEVELOPER_ID_PROVISION_PROFILE_BASE64`.

Create the profile in Apple Developer > Certificates, Identifiers & Profiles > Profiles:

1. Select Developer ID.
2. Select the Auth macOS App ID, `io.ente.auth.mac`.
3. Select the Developer ID Application certificate stored in `MAC_OS_CERTIFICATE`.
4. Set `AUTH_MACOS_DEVELOPER_ID_PROVISION_PROFILE_BASE64` to the base64 of the downloaded profile.

Regenerate the profile when the App ID entitlements or Developer ID certificate change.

## Per-app iOS setup

Each iOS app needs its own App ID, App Store Connect app, and App Store provisioning profile. The Apple Distribution certificate and App Store Connect API key are reused across apps.

### App ID

In Apple Developer > Certificates, Identifiers & Profiles > Identifiers, create an explicit App ID for the app's bundle ID, for example `io.ente.<app>`. Enable only the capabilities the app actually uses.

### App Store Connect app

In App Store Connect > Apps, create the app record and select the App ID from the previous step.

### App Store provisioning profile

The iOS archive is manually signed. `-allowProvisioningUpdates` lets Xcode download the existing profile from Apple; the profile itself is not stored in GitHub secrets, but it does need to exist in the portal.

In Apple Developer > Certificates, Identifiers & Profiles > Profiles, create a new distribution profile:

1. Select App Store Connect.
2. Select the app's App ID.
3. Select the Apple Distribution certificate stored in `APPLE_DISTRIBUTION_CERT_BASE64`.
4. Name the profile `<App> App Store`.
5. Generate it.

Use the distribution channel as the profile name: `<App> App Store`.

For another iOS app, reuse the same Apple Distribution certificate and App Store Connect API key, but create a separate App Store provisioning profile for that app's bundle ID.

If the app ships extensions, create one App ID and one App Store profile per shipped bundle ID.

Photos:

- `io.ente.frame` -> `Photos App Store`
- `io.ente.frame.ShareExtension` -> `Photos Share Extension App Store`
- `io.ente.frame.EnteAlbumWidget` -> `Photos Album Widget App Store`
- `io.ente.frame.EnteMemoryWidget` -> `Photos Memory Widget App Store`
- `io.ente.frame.EntePeopleWidget` -> `Photos People Widget App Store`

Auth:

- `io.ente.auth` -> `Auth App Store`

Locker:

- `io.ente.locker` -> `Locker App Store`
- `io.ente.locker.Share-Extension` -> `Locker Share Extension App Store`

Ensu:

- `io.ente.ensu` -> `Ensu App Store`

### Entitlements

When adding new entitlements, the profile needs to be regenerated.

1. Go to Apple Developer > Certificates, Identifiers & Profiles > Identifiers > `io.ente.<app>`.
2. Enable the missing capability and save the App ID.
3. Go to Profiles and regenerate/save the XXX App Store profile. Keep the profile name exactly the same.

## Profile rotation

Provisioning profiles are tied to the Apple Distribution certificate selected when they are generated. When the Apple Distribution certificate changes, regenerate the App Store profiles for every app that should use the new certificate.

Keep profile names stable during renewal so workflows do not need code changes. If a profile name does change, update the app's signing configuration wherever that profile specifier is referenced.

The provisioning profile is not stored in GitHub secrets. It exists in the Apple Developer portal, and `xcodebuild -allowProvisioningUpdates` downloads it during the build using the App Store Connect API key.
