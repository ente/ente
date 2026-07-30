# HEIC conversion

## What

**HEIF** is a container format.

- It was developed by Nokia, which also provides a reference implementation that no one (?) uses (it has some samples though - https://github.com/nokiatech/heif/tree/gh-pages/content).

- The de-facto implementation is **libheif** (https://github.com/strukturag/libheif).

**HEIF** can contain HEVC and AV1 data.

- HEIF can contain one or more images (e.g burst photos)

- These images can have arbitrary codecs like HEVC, AV1, or even JPEG.

**HEVC**, aka H.265, is a video codec.

- It is the successor of H.264.

- The de-facto implementation is x265, by the VLC folks (https://www.videolan.org/developers/x265.html). aka **libx265**.

- Since x265 is GPL, a popular LGPL alternative H.265 decoder (only) is **libde265** by the same folks who make libheif (https://github.com/strukturag/libde265).

- A new, still WIP, alternative encoder is https://github.com/ultravideo/kvazaar.

**AV1** is a video codec.

- It is made by a pool of companies, AOM (Alliance for Open Media), as a royalty free alternative to H.265.

**AVIF** files are HEIF container and AV1 codec.

- They're supported by all major browsers.

**HEIC** files are HEIF container and HEVC codec.

- iPhones and Samsung Galaxy use them as the default.

- They're only supported by Safari (latest).

## FFmpeg

FFmpeg (and its native library, libavcodec) supports HEVC.

- Default software codec is libx265.

- Hardware support is platform specific. On macOS `ffmpeg -codecs` lists `hevc_videotoolbox` as a codec. Video Toolbox is Apple's access to hardware encoders / decoders (https://developer.apple.com/documentation/videotoolbox)

FFmpeg, as of 2024, partially supports converting HEIC files

- "So once this patch is applied, the only unsupported items would be Alpha and Grid (Tiles) for both AVIF and HEIC." ([ref](https://patchwork.ffmpeg.org/project/ffmpeg/patch/20230926173742.2623244-1-vigneshv@google.com/#80191))

- This partial support is not enough. Trying `ffmpeg -i 1.heic 1.jpeg` on a photo taken by iPhone (iOS 18) gives only a small area of the image. The upstream issue - [Support merging HEIC tile grids in ffmpeg](https://trac.ffmpeg.org/ticket/11170) - mentions a workaround by combining the grid but that produces a thick gray border on the right and bottom (and the orientation is also not respected).

FFmpeg support would be nice since we already bundle it both in the desktop app and also as a web Wasm build.

---

## libheif + libde265

Every other HEIC converter, binary or library (e.g. ImageMagick, GraphicsMagick, libvips, sharp and wasm-vips), I've seen eventually the uses the combination of libheif (for the HEIF container) + libde265 (for the HEVC decoding), with an option to swap libde265 with libx265 or kvazaar.

Currently our web app uses [heic-convert](https://github.com/catdad-experiments/heic-convert), which provides packaged Wasm builds of libheif + libde265, and the desktop app uses a [custom build](https://github.com/ente/libvips-packaging) of `vips` on Linux and Windows, and Apple's `sips` on macOS.
