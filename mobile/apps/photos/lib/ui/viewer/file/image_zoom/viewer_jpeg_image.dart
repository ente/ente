import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";

bool isViewerJpeg(EnteFile file) {
  if (file.fileType != FileType.image && file.fileType != FileType.livePhoto) {
    return false;
  }
  final name = (file.title ?? file.displayName).toLowerCase();
  return name.endsWith(".jpg") || name.endsWith(".jpeg");
}

@immutable
class ViewerJpegImage extends ImageProvider<ViewerJpegImage> {
  final File file;
  final int width;
  final int height;

  ViewerJpegImage.fit(this.file, Size physicalViewport)
    : width = physicalViewport.width.ceil(),
      height = physicalViewport.height.ceil();

  @override
  Future<ViewerJpegImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ViewerJpegImage key,
    ImageDecoderCallback decode,
  ) {
    late final _ViewerJpegStream stream;
    Future<ui.Codec> load() async {
      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      return decode(
        buffer,
        getTargetSize: (sourceWidth, sourceHeight) {
          stream.sourceSize = Size(
            sourceWidth.toDouble(),
            sourceHeight.toDouble(),
          );
          return targetSizeFor(stream.sourceSize);
        },
      );
    }

    stream = _ViewerJpegStream(codec: load());
    stream.addEphemeralErrorListener((_, _) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return stream;
  }

  @visibleForTesting
  ui.TargetImageSize targetSizeFor(Size source) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      source,
      Size(width.toDouble(), height.toDouble()),
    ).destination;
    // Skia decodes JPEGs in eighths. Rounding down can soften the fitted image.
    for (var eighths = 1; eighths < 8; eighths++) {
      final decodeWidth = (source.width * eighths / 8).ceil();
      final decodeHeight = (source.height * eighths / 8).ceil();
      if (decodeWidth >= fitted.width && decodeHeight >= fitted.height) {
        return ui.TargetImageSize(width: decodeWidth, height: decodeHeight);
      }
    }
    return ui.TargetImageSize(
      width: source.width.toInt(),
      height: source.height.toInt(),
    );
  }

  Future<Size> prepare(ImageConfiguration configuration) {
    final stream = resolve(configuration);
    final result = Completer<Size>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        if (result.isCompleted) {
          image.dispose();
          return;
        }
        final completer = stream.completer! as _ViewerJpegStream;
        result.complete(completer.sourceSize);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          stream.removeListener(listener);
          image.dispose();
        });
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        result.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return result.future;
  }

  @override
  bool operator ==(Object other) =>
      other is ViewerJpegImage &&
      file.path == other.file.path &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(file.path, width, height);
}

// A cache hit reuses the stream without reading the original's header again.
class _ViewerJpegStream extends MultiFrameImageStreamCompleter {
  late Size sourceSize;

  _ViewerJpegStream({required super.codec}) : super(scale: 1);
}
