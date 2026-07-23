---
title: Ensu - Changelog
description: Release notes of recent updates to Ensu
---

# Changelog - Ensu

A short summary list of changes to the Ensu mobile and desktop apps. For a more descriptive list with screenshots and blog post links, see the [news](https://ente.com/news).

## v0.1.17 - Jun 2026

- Fixed the desktop app version shown in settings.
- Updated JNA library to satisfy Android's 16 KB page size requirement.
- Added support for dragging and dropping images into desktop chat attachments.
- Migrated the desktop app to Tauri v2.
- Added a mobile device memory check to disable local chat on devices with less than 4 GB of RAM

## v0.1.16 - May 2026

- Added Gemma 4 for the desktop app.
- Added local voice transcription for chat input on iOS and Android.
- Improved image attachments with compression, thumbnails, full-screen previews, and cleaner composer previews.
- Improved image prompt performance on native apps by resizing to model limits and caching multimodal context.
- Added in-app changelogs to desktop, Android, and iOS.
- Balanced haptics on mobile to once at the start of response generation.
- Improved model downloads with shared native downloading, cache reuse, parallel/range downloads, retries, and better progress reporting.
- Improved desktop model selection by using better system memory detection.
- Fixed Android back button handling when the sidebar is open.
- Fixed the desktop app version shown in settings.

## v0.1.15 - Apr 2026

- Added auto updates for Linux, macOS, and Windows.
- Fixed crash on exit on macOS.

## v0.1.14 - Mar 2026

- Added DMGs for Apple Silicon.
- Pruned Windows builds.

## v0.1.12 - Mar 2026

- Advanced model settings for power users: choose from preset models or bring your own.
- Customizable system prompt on all platforms.
- Smart default model selection based on your device's available memory (desktop).
- Native inline math rendering on chat messages.
- Model downloads now resume automatically after app restarts or interruptions.
- Smarter retry behavior for interrupted assistant responses.
- Smoother mobile chat experience with better keyboard and scroll handling.

## v0.1.5 - Mar 2026

- Improvements to desktop builds.

## v0.1.3 - Mar 2026

- Initial release of Ensu, Ente's local LLM app: a private, on-device AI that works offline. Cross-platform, open source, and powered by a shared Rust core.
