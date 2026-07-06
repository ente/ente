---
title: Ente Auth - Changelog
description: Release notes of recent updates to Ente Auth
---

# Changelog - Ente Auth

A short summary list of changes to the Ente Auth mobile and desktop apps. For a more descriptive list with screenshots and blog post links, see the [news](https://ente.com/news).

## v4.4.24 - Jul 2026

- Added a way to view and delete Auth codes that could not be parsed.
- Added support for importing 2FA codes from QR code images on desktop.
- Improved support for importing codes from Google Authenticator QR exports.
- Fixed Auth AppImage startup on Linux systems where bundled C++ runtime libraries could conflict with host graphics drivers.
- Fixed Auth AppImage startup on Linux systems where bundled dependencies could not find libffi.
- Fixed Auth deb installs missing Linux runtime dependencies on fresh systems.
- Matched the Auth Linux title bar to GNOME's dark mode preference.
- Fixed Auth Linux pacman package dependency metadata so libsodium is installed for crypto initialization.
- Improved Linux setup guidance when system authentication needs extra setup.
- Fixed Auth startup crashes on Linux X11 sessions caused by Xlib threading initialization.
- Improved QR code detection when importing from low-resolution gallery images.
- Improved QR scanner camera focusing and device compatibility.
- Added a scan frame and torch control to the QR scanner.
- Fixed QR scanner black screens when adding codes.
- Improved animation smoothness for Auth on Windows high-refresh-rate displays.

## v4.4.23 - Jun 2026

- Newly added codes now stay in view, so an active search or tag filter no longer hides a code you just added.
- Sharing is now limited to TOTP codes; the share option is hidden for HOTP entries.
- Fixed many custom icons that were invisible, low-contrast, mis-colored, or flickering in light or dark mode.
- Fixed some icons not appearing in the icon picker because their filenames weren't resolved correctly.
- Added custom icons for several more services.
- Your selected theme on Desktop is now kept after unlocking, and the lock screen no longer shows the old theme after you change it in-app.
- Tag strips that overflow can now be scrolled with the mouse wheel or by dragging, and tag chips are reachable with Tab and selectable with Enter or Space.
- Better support for linux system authentication.
- Fixed AppImage startup failures on some Linux systems by preferring host libraries before bundled fallbacks.
- Fixed missing tray icons in sandboxed Linux builds.
- Fixed Windows tray close, exit, and menu actions, removed stale/duplicate tray icons, and improved tray icon contrast in the overflow.
- Worked around the keyboard not reliably opening for search and app-lock password fields on app start
- Moved Auth services to ente.com domains.
- Updated Estonian, Hungarian, Lithuanian, Portuguese, and Russian translations.

## v4.4.22 - May 2026

- Added support for search deep links via enteauth://search.
- Improved Proton Authenticator import, including support for encrypted exports.
- Improved QR/image import reliability, including better cleanup of temporary picked images.
- Reduced duplicate sync work during bulk code imports and updates.
- Fixed desktop stability issues, including Linux close behavior and macOS build fixes.
- Updated app links, translations, icons, and store metadata.

## v4.4.17 - Feb 2026

- New login/sign up screens
- Bug fixes and improvements

## v4.4.15 - Dec 2025

- Icon picker
- New QR code designs
- Import andOTP backups

## v4.4.12 - Nov 2025

- Continuous on-device backups
- Notes in search results
- Quick settings tile on Android
- Custom sort improvements
- Improved new user experience
- Bug fixes and other improvements

## v4.4.10 - Nov 2025

- New icon!
- Multi-select! Select multiple codes to perform actions in one go
- Import 2FA codes from gallery
- Support Google Authenticator when exporting QR

## v4.4.4 - Aug 2025

- Lots of new custom icons!
- Add monochrome icon style for macOS tray
- Auto hide dock icon macOS

## v4.4.3 - Jul 2025

- Fix unknown hard error on closing the app on Windows
- Fall back to Passcode if FaceId not detected on iOS

## v4.4.0 - Jun 2025

- Handle incorrect system time during code generation (online mode only)
- Sign windows build using Azure trust signing
