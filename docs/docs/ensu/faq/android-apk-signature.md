---
title: Verify the Ensu Android APK
description: Check the signing certificate fingerprints for the Ensu APK downloaded directly from GitHub releases
---

# Verify the Ensu Android APK

If you downloaded the Ensu APK directly from our GitHub releases, you can verify that it was signed with Ente's expected signing certificate.

These fingerprints are for the direct APK download. Play Store packages may use different signing keys.

## Certificate fingerprints

- **SHA1**: 55:32:94:80:28:F7:C7:43:9F:41:07:58:4B:13:F1:56:38:00:75:0C
- **SHA256**: 66:99:CF:8C:42:AF:42:7B:55:2C:96:20:54:E5:D6:95:89:FA:49:09:96:55:3A:53:04:5E:B3:9C:C3:4F:2E:66

## Verify the APK

```sh
apksigner verify --print-certs <path_to_apk>
```

Compare the `SHA1` or `SHA256` value printed by `apksigner` with the fingerprints above. Note that `apksigner` prints certificate fingerprints using lowercase letters and without colons:

```text
Signer #1 certificate SHA-256 digest: 6699cf8c42af427b552c962054e5d69589fa490996553a53045eb39cc34f2e66
```
