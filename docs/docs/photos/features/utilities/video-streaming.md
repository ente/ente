---
title: Video Streaming
description: Stream your videos without downloading them first
---

# Video Streaming

Video streaming is a beta feature that lets you watch videos without downloading the entire file first. Instead of downloading the full video, Ente generates a streamable version that supports instant playback and seeking.

> [!NOTE]
>
> Video streaming is available in beta on mobile apps starting v0.9.98 and on desktop starting v1.7.13.

## How it works

When you enable video streaming, Ente generates streamable versions (HLS format) of your videos that support:

- **Instant playback** - Start watching immediately without waiting for downloads
- **Seeking/scrubbing** - Jump to any point in the video without downloading the whole file
- **Automatic quality selection** - Optimized playback based on your connection

### Technical details

Streams are encrypted HLS files with a `.m3u8` playlist. Currently, Ente converts videos to:

- Resolution: 720p
- Bitrate: 2mbps
- Format: H.264

The generated stream is a single encrypted blob (AES encryption) while the playlist file (`.m3u8`) is separately encrypted using XChaCha20. Ente cannot read the contents, duration, or number of chunks within the generated stream due to encryption.

## Enabling video streaming

### On mobile

1. Open `Settings > Streamable videos`
2. Enable the toggle

**What happens next:**

- Videos captured in the last 60 days and under 1 minute will start processing automatically
- Local videos will be processed

**For older or longer videos:**

Open the specific video, tap the overflow menu (⋮) in the top-right corner, and select **Create stream**

### On desktop

1. Open `Settings > Preferences > Streamable videos`
2. Enable the toggle

**What happens next:**

- New uploads will automatically generate streams
- All existing previously uploaded videos will be processed
- Stream generation is CPU intensive and happens in the background
- Click the search bar to see "Processing videos..." status
- Processed videos sync to mobile automatically

## Viewing video streams

### On mobile

- Open `Settings > Backup > Backup status` to see processing status
- Processed videos show a green play button
- Tap processed videos to see a `Play stream` button
- Click the `Info` icon within a video to see stream details

### On desktop and web

- Desktop and web automatically play streaming versions if available
- The quality selector shows "Auto" when playing a stream

## Storage implications

**While this feature is in beta**, streams do not count against your storage quota.

This may change in the future. If it does, we will provide an option to choose:

1. Original videos only
2. Compressed streams only
3. Both (original + streams)

## Related FAQs

- [What is video streaming technically?](/photos/faq/advanced-features#what-is-a-stream)
- [Will streams consume my storage?](/photos/faq/advanced-features#stream-storage)
- [How do I report issues?](/photos/faq/advanced-features#stream-issues)
- [App crashes with video streaming enabled](/photos/faq/advanced-features#app-crashes-video-streaming)
- [Video upload failures with streaming enabled](/photos/faq/advanced-features#video-upload-failures-streaming)
