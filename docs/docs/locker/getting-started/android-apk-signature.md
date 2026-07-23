---
title: Verify the Ente Locker Android APK
description: Check the signing certificate fingerprints for the Ente Locker APK downloaded directly from GitHub releases
---

# Verify the Ente Locker Android APK

If you downloaded the Ente Locker APK directly from our GitHub releases, you can verify that it was signed with Ente's expected signing certificate.

These fingerprints are for the direct APK download. Play Store and F-Droid packages may use different signing keys.

## Certificate fingerprints

- **SHA1**: EF:BA:46:7F:BE:E2:F7:9A:0C:A7:76:A2:9D:AA:70:13:B9:B7:AE:D2
- **SHA256**: 6E:5B:71:61:B0:FA:F1:01:B6:AF:3D:33:C6:B0:8C:AD:AC:4A:8B:DF:85:E5:BE:A5:06:83:AA:FA:74:05:0D:B1

## Verify the APK

```sh
apksigner verify --print-certs <path_to_apk>
```

Compare the `SHA1` or `SHA256` value printed by `apksigner` with the fingerprints above. Note that `apksigner` prints certificate fingerprints using lowercase letters and without colons:

```text
Signer #1 certificate SHA-256 digest: 6e5b7161b0faf101b6af3d33c6b08cadac4a8bdf85e5bea50683aafa74050db1
```
