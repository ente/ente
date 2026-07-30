---
title: Installing Ente Auth
description: Steps to install Ente Auth
---

# Android

Our Android apps are distributed over the following channels.

### PlayStore

You can install Auth directly from [PlayStore](https://play.google.com/store/apps/details?id=io.ente.auth).

### F-Droid

Reproducible builds for Auth are available on [F-Droid](https://f-droid.org/packages/io.ente.auth/).

> [!NOTE]
>
> Releases over F-Droid are generally slower since they run their own build servers. You can donate to F-Droid [here](https://f-droid.org/en/donate).

### GitHub

Latest releases are built straight from the source and made available over [GitHub](https://github.com/ente/ente/releases?q=tag%3Aauth-v4).

These builds will notify you whenever a new release is available and will help you stay updated.

If you install the APK directly from GitHub, see [Verify the Ente Auth Android APK](/auth/faq/android-apk-signature).

### Obtainium

You can setup [Obtainium](https://github.com/ImranR98/Obtainium) to track our GitHub releases by [clicking this link](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.ente.auth.independent%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fente%2Fente%22%2C%22author%22%3A%22ente%22%2C%22name%22%3A%22Ente%20Auth%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Atrue%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Afalse%2C%5C%22releaseTitleAsVersion%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22versionExtractionRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22matchGroupToUse%5C%22%3A%5C%22%5C%22%2C%5C%22versionDetection%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Afalse%2C%5C%22useVersionCodeAsOSVersion%5C%22%3Afalse%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22ente-auth*%5C%22%2C%5C%22invertAPKFilter%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Atrue%2C%5C%22appName%5C%22%3A%5C%22%5C%22%2C%5C%22shizukuPretendToBeGooglePlay%5C%22%3Afalse%2C%5C%22allowInsecure%5C%22%3Afalse%2C%5C%22exemptFromBackgroundUpdates%5C%22%3Afalse%2C%5C%22skipUpdateNotifications%5C%22%3Afalse%2C%5C%22about%5C%22%3A%5C%22%5C%22%7D%22%2C%22overrideSource%22%3Anull%7D) to add it instantly.

Alternatively, you can follow these steps:

1. Click **Add App** to open a new app config screen
2. Enter `https://github.com/ente/ente` in the **App Source URL** field
3. Enable the **Retain release order** from API toggle
4. Scroll down to the **Filter APKs by Regular Expression** field and enter `ente-auth*`
5. Enable the **Attempt to filter APKs by CPU architecture** if possible toggle
6. Select any applicable app category labels you may have setup
7. Enable the **Try inferring app ID from source code** toggle
8. Scroll back to the top and click **Add** to complete the setup

<br/>

---

<br/>

# iOS

You can install Ente Auth on Apple devices from [AppStore](https://apps.apple.com/us/app/ente-auth/id6444121398).

<br/>

---

<br/>

# Desktop

You can grab the latest version of Ente Auth for Mac, Windows and Linux from [GitHub](https://github.com/ente/ente/releases?q=tag%3Aauth-v4).

On Linux, App lock can use system authentication in releases newer than `auth-v4.4.22`. Learn how to [set up Linux system authentication](/auth/troubleshooting/linux-system-auth).

<br/>

---

<br/>

# Web

Latest versions of our web app are available at [auth.ente.com](https://auth.ente.com).

> [!NOTE]
>
> The older `auth.ente.io` address now redirects to `auth.ente.com`. Your same Ente account and password continue to work there. If your password manager suggests a login saved for the older address, you can use it on `auth.ente.com`.

<br/>

---

<br/>

### What Windows version does Ente Auth run on? {#windows-version}

The Ente Auth desktop app requires Windows 10 or later. Windows 7 and 8 are not supported.

---

# CLI

Ente's CLI is distributed directly over [GitHub](https://github.com/ente/ente/releases?q=tag%3Acli-v0).
