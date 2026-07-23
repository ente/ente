---
title: Video Editor
description: Edit your videos with trim, crop, and rotate tools
---

# Video Editor

The video editor lets you make basic edits to your videos directly within Ente Photos. Edit videos with trim, crop, and rotate tools, and save them as new copies while preserving your originals.

> [!NOTE]
>
> The video editor was revamped in v1.2.18 to drastically improve speed when editing larger videos and enhance the user experience.

## Features

The video editor supports three main editing operations:

### Trim

Cut your videos to the exact length you need:

- Set start and end points using the timeline slider
- Preview your selection before saving
- Minimum video duration: 1 second
- View trimmed duration in real-time

### Crop

Adjust the video frame to different aspect ratios or custom dimensions:

**Available aspect ratios:**

- **Free** - Manually adjust the crop area without constraints
- **1:1** - Square format (Instagram posts)
- **9:16** - Vertical format (Instagram Stories, TikTok)
- **16:9** - Widescreen format (YouTube, most videos)
- **3:4** - Vertical portrait
- **4:3** - Classic format

The crop tool automatically accounts for video rotation, ensuring the aspect ratio appears correctly in the final output.

### Rotate

Rotate videos in 90-degree increments:

- **Rotate left** - Counter-clockwise 90°
- **Rotate right** - Clockwise 90°

Useful for correcting videos captured in the wrong orientation.

## How to use the video editor

**On mobile:**

1. Open any video in your library
2. Tap the overflow menu (⋮) and select **Edit**
3. The video editor opens with three action buttons at the bottom:
    - **Trim** - Adjust video length
    - **Crop** - Change video dimensions
    - **Rotate** - Change video orientation
4. Make your edits using one or more tools
5. Tap **Save copy** to create the edited version

**What happens when you save:**

- Ente creates a new video file with your edits applied
- The original video remains unchanged
- The new video preserves:
    - Creation time from the original
    - Location data (if available)
    - Collection/album membership
- The edited video automatically syncs to your account
- Both videos appear in your library

## Video preview and playback

While editing:

- Preview your changes in real-time
- Use playback controls to review specific sections
- Play/pause the video to verify your edits
- Seek through the timeline to check different moments

The preview shows exactly how your edited video will look, including all applied transformations.

## Technical details

### Export methods

Ente uses two export methods to ensure compatibility across devices:

1. **Native export** (default)
    - **iOS**: Uses AVFoundation with HighestQuality preset or Passthrough (no re-encoding for simple trims)
    - **Android**: Uses Media3 Transformer with H.264 encoding
    - Faster performance and better quality preservation
    - Hardware-accelerated on supported devices
    - **Output**: MP4 with H.264 video, maintains original quality when possible

2. **FFmpeg fallback**
    - Automatically used if native export fails
    - Cross-platform software-based encoding
    - **Output**: MP4 with H.264 video (libx264), AAC audio

The app automatically switches between methods to ensure your edits can be saved successfully.

### Output format

All edited videos are exported as MP4 files:

- **File naming**: `[original-name]_edited_[timestamp].mp4`
- **Resolution**: Preserves original resolution when possible
- **Quality**: Native export maintains highest quality; FFmpeg uses standard H.264/AAC encoding

### Processing time

Export time depends on:

- Video duration and resolution
- Number of edits applied
- Device processing power
- Export method used (native vs FFmpeg)

A progress dialog shows the export status while your video is being processed.

## Limitations

- **Minimum duration**: Videos must be at least 1 second long after trimming
- **Mobile only**: Currently available on iOS and Android apps only
- **Single video editing**: Edit one video at a time
- **Destructive workflow**: Cannot save edit settings - each export creates a final video
