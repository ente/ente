---
title: Verify the Ente Photos Android APK
description: Check the signing certificate fingerprints for the Ente Photos APK downloaded directly from GitHub releases
---

# Verify the Ente Photos Android APK

If you downloaded the Ente Photos APK directly from our GitHub releases, you can verify that it was signed with Ente's expected signing certificate.

These fingerprints are for the direct APK download. Play Store and F-Droid packages may use different signing keys.

## Certificate fingerprints

- **SHA1**: E1:60:10:18:B6:B0:2E:A3:74:6F:90:67:50:30:29:75:0E:EF:6D:39
- **SHA256**: 35:ED:56:81:B7:0B:B3:BD:35:D9:0D:85:6A:F5:69:4C:50:4D:EF:46:AA:D8:3F:77:7B:1C:67:5C:F4:51:35:0B

## Verify the APK

```sh
apksigner verify --print-certs <path_to_apk>
```

Compare the `SHA1` or `SHA256` value printed by `apksigner` with the fingerprints above. Note that `apksigner` prints certificate fingerprints using lowercase letters and without colons:

```text
Signer #1 certificate SHA-256 digest: 35ed5681b70bb3bd35d90d856af5694c504def46aad83f777b1c675cf451350b
```
