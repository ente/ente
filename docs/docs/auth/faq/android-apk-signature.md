---
title: Verify the Ente Auth Android APK
description: Check the signing certificate fingerprints for the Ente Auth APK downloaded directly from GitHub releases
---

# Verify the Ente Auth Android APK

If you downloaded the Ente Auth APK directly from our GitHub releases, you can verify that it was signed with Ente's expected signing certificate.

These fingerprints are for the direct APK download. Play Store and F-Droid packages may use different signing keys.

## Certificate fingerprints

- **SHA1**: 57:E8:C6:59:C3:AA:C9:38:B0:10:70:5E:90:85:BC:20:67:E6:8F:4B
- **SHA256**: BA:8B:F0:32:98:62:70:05:ED:DF:F6:B1:D6:0B:3B:FA:A1:4E:E8:BD:C7:61:4F:FB:3B:B1:1C:58:8D:9E:3A:D7

## Verify the APK

```sh
apksigner verify --print-certs <path_to_apk>
```

Compare the `SHA1` or `SHA256` value printed by `apksigner` with the fingerprints above. Note that `apksigner` prints certificate fingerprints using lowercase letters and without colons:

```text
Signer #1 certificate SHA-256 digest: ba8bf03298627005eddff6b1d60b3bfaa14ee8bdc7614ffb3bb11c588d9e3ad7
```
