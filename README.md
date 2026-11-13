<div align="center">

<img src=".github/assets/ente-rocketship.png" width="400"/>

Fully open source end-to-end encrypted photos, authenticators and more.

</div>

# Ente

Ente is a service that provides a fully open source, end-to-end encrypted platform for you to store your data in the cloud without needing to trust the service provider. On top of this platform, we have built three apps so far: Ente Photos (an alternative to Apple and Google Photos), Ente Locker (a safe space for your most important documents and credentials), and Ente Auth (a 2FA alternative to the deprecated Authy).

This monorepo contains all our source code - the client apps (iOS / Android / F-Droid / Web / Linux / macOS / Windows) for both the products (and more planned future ones!), and the server that powers them.

Our source code and cryptography have been externally audited by Cure53 (a German cybersecurity firm, arguably the world's best), Symbolic Software (French cryptography experts) and Fallible (an Indian penetration testing firm).

Learn more at [ente.com](https://ente.com).

<br />

## Ente Photos

![Screenshots of Ente Photos](.github/assets/photos.png)

Our flagship product. 3x data replication. Face detection. Semantic search. Private sharing. Collaborative albums. Family plans. Easy import, easier export. Background uploads. The list goes on. And of course, all of this, while being fully end-to-end encrypted across platforms.

Ente Photos is a paid service, but we offer 10GB of free storage. You can also clone this repository and choose to self-host.

<br />

<div align="center">

[<img height="40" src=".github/assets/app-store-badge.svg">](https://apps.apple.com/app/id1542026904)
[<img height="40" src=".github/assets/play-store-badge.png">](https://play.google.com/store/apps/details?id=io.ente.photos)
[<img height="40" src=".github/assets/f-droid-badge.png">](https://f-droid.org/packages/io.ente.photos.fdroid/)
[<img height="40" src=".github/assets/obtainium-badge.png">](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.ente.photos.independent%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fente%2Fente%22%2C%22author%22%3A%22ente%22%2C%22name%22%3A%22Ente%20Photos%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Atrue%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Afalse%2C%5C%22releaseTitleAsVersion%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22versionExtractionRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22matchGroupToUse%5C%22%3A%5C%22%5C%22%2C%5C%22versionDetection%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Afalse%2C%5C%22useVersionCodeAsOSVersion%5C%22%3Afalse%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22ente-photos*%5C%22%2C%5C%22invertAPKFilter%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Atrue%2C%5C%22appName%5C%22%3A%5C%22%5C%22%2C%5C%22shizukuPretendToBeGooglePlay%5C%22%3Afalse%2C%5C%22allowInsecure%5C%22%3Afalse%2C%5C%22exemptFromBackgroundUpdates%5C%22%3Afalse%2C%5C%22skipUpdateNotifications%5C%22%3Afalse%2C%5C%22about%5C%22%3A%5C%22%5C%22%7D%22%2C%22overrideSource%22%3Anull%7D)
[<img height="40" src=".github/assets/desktop-badge.png">](https://ente.com/download/desktop)
[<img height="40" src=".github/assets/web-badge.svg">](https://photos.ente.com)

</div>

<br />

## Ente Auth

![Screenshots of Ente Photos](.github/assets/auth.png)

Our labour of love. Two years ago, while building Ente Photos, we realized that there was no open source end-to-end encrypted authenticator app. We already had the building blocks, so we built one.

Ente Auth is free, and will remain free forever. If you like the service and want to give back, please check out Ente Photos or spread the word.

<br />

<div align="center">

[<img height="40" src=".github/assets/app-store-badge.svg">](https://apps.apple.com/app/id6444121398)
[<img height="40" src=".github/assets/play-store-badge.png">](https://play.google.com/store/apps/details?id=io.ente.auth)
[<img height="40" src=".github/assets/f-droid-badge.png">](https://f-droid.org/packages/io.ente.auth/)
[<img height="40" src=".github/assets/obtainium-badge.png">](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.ente.auth.independent%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fente%2Fente%22%2C%22author%22%3A%22ente%22%2C%22name%22%3A%22Ente%20Auth%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Atrue%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Afalse%2C%5C%22releaseTitleAsVersion%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22versionExtractionRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22matchGroupToUse%5C%22%3A%5C%22%5C%22%2C%5C%22versionDetection%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Afalse%2C%5C%22useVersionCodeAsOSVersion%5C%22%3Afalse%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22ente-auth*%5C%22%2C%5C%22invertAPKFilter%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Atrue%2C%5C%22appName%5C%22%3A%5C%22%5C%22%2C%5C%22shizukuPretendToBeGooglePlay%5C%22%3Afalse%2C%5C%22allowInsecure%5C%22%3Afalse%2C%5C%22exemptFromBackgroundUpdates%5C%22%3Afalse%2C%5C%22skipUpdateNotifications%5C%22%3Afalse%2C%5C%22about%5C%22%3A%5C%22%5C%22%7D%22%2C%22overrideSource%22%3Anull%7D)
[<img height="40" src=".github/assets/desktop-badge.png">](https://github.com/ente/ente/releases?q=tag%3Aauth-v4)
[<img height="40" src=".github/assets/web-badge.svg">](https://auth.ente.com)

</div>

<br />

## Ente Locker

![Screenshots of Ente Locker](.github/assets/locker.png)

Protect your most important documents, credentials, and notes with end-to-end encryption. Share privately with people you trust, and set up access for emergencies. Available for iOS and Android.

Ente Locker is free for up to 100 items. If you're subscribed to Ente Photos, you can store up to 1000 items. Learn more at [ente.com/locker](https://ente.com/locker).

<div align="center">

[<img height="40" src=".github/assets/app-store-badge.svg">](https://apps.apple.com/us/app/ente-locker/id6747611956)
[<img height="40" src=".github/assets/play-store-badge.png">](https://play.google.com/store/apps/details?id=io.ente.locker)
[<img height="40" src=".github/assets/obtainium-badge.png">](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.ente.locker.independent%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fente%2Fente%22%2C%22author%22%3A%22ente%22%2C%22name%22%3A%22Ente%20Locker%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Atrue%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Afalse%2C%5C%22releaseTitleAsVersion%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22versionExtractionRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22matchGroupToUse%5C%22%3A%5C%22%5C%22%2C%5C%22versionDetection%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Afalse%2C%5C%22useVersionCodeAsOSVersion%5C%22%3Afalse%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22ente-locker*%5C%22%2C%5C%22invertAPKFilter%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Atrue%2C%5C%22appName%5C%22%3A%5C%22%5C%22%2C%5C%22shizukuPretendToBeGooglePlay%5C%22%3Afalse%2C%5C%22allowInsecure%5C%22%3Afalse%2C%5C%22exemptFromBackgroundUpdates%5C%22%3Afalse%2C%5C%22skipUpdateNotifications%5C%22%3Afalse%2C%5C%22about%5C%22%3A%5C%22%5C%22%7D%22%2C%22overrideSource%22%3Anull%7D)

</div>

<br />

## Contributing

Want to get aboard the Ente hype train? Welcome along! Don't hesitate if you're not a developer, there are many other important ways in which [you can contribute](CONTRIBUTING.md).

## Support

We are never more than an email away. For the various ways to ask for help, please see our [support guide](SUPPORT.md).

## Community

<img src=".github/assets/ente-ducky.png" width=200 alt="Ente's Mascot, Ducky,
    inviting people to Ente's source code repository" />

Please visit the [community section](https://ente.com/about#community) for all the ways to connect with our community.

[![Discord](https://img.shields.io/discord/948937918347608085?style=for-the-badge&logo=Discord&logoColor=white&label=Discord)](https://discord.gg/z2YVKkycX3)
[![Ente's Blog RSS](https://img.shields.io/badge/blog-rss-F88900?style=for-the-badge&logo=rss&logoColor=white)](https://ente.com/blog/rss.xml)

[![Twitter](.github/assets/twitter.svg)](https://twitter.com/enteio) &nbsp; [![Mastodon](.github/assets/mastodon.svg)](https://fosstodon.org/@ente)

---

## Security

If you believe you have found a security vulnerability, please responsibly disclose it by emailing security@ente.com or [using this link](https://github.com/ente/ente/security/advisories/new) instead of opening a public issue. We will investigate all legitimate reports. To know more, please see our [security policy](SECURITY.md).
