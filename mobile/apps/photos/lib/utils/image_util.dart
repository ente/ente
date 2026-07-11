import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

final _logger = Logger("ImageUtil");

const Set<String> _rawImageExtensions = {
  'arw', // Sony
  'cr2', 'cr3', // Canon
  'nef', 'nrw', // Nikon
  'dng', // Adobe/generic
  'orf', // Olympus
  'raf', // Fuji
  'rw2', // Panasonic
  'pef', // Pentax
  'srw', // Samsung
  '3fr', 'fff', // Hasselblad
  'rwl', // Leica
  'x3f', // Sigma
  'iiq', // Phase One
  'kdc', 'dcr', // Kodak
  'mrw', // Minolta
  'erf', // Epson
  'mef', // Mamiya
  'raw', // Generic
};

bool isRawImageExtension(String extension) =>
    _rawImageExtensions.contains(extension.toLowerCase());

Future<ImageInfo> getImageInfo(ImageProvider imageProvider) {
  final completer = Completer<ImageInfo>();
  final imageStream = imageProvider.resolve(const ImageConfiguration());
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (imageInfo, _) {
      if (completer.isCompleted) return;
      imageStream.removeListener(listener);
      completer.complete(imageInfo);
    },
    onError: (error, stackTrace) {
      if (completer.isCompleted) return;
      imageStream.removeListener(listener);
      completer.completeError(error, stackTrace ?? StackTrace.current);
    },
  );
  imageStream.addListener(listener);
  return completer.future;
}

Future<({int width, int height})?> getImageDimensions({
  String? imagePath,
  Uint8List? imageBytes,
}) async {
  if (imagePath == null && imageBytes == null) {
    throw ArgumentError("imagePath and imageBytes cannot be null");
  }
  try {
    late Uint8List bytes;
    if (imagePath != null) {
      bytes = await File(imagePath).readAsBytes();
    } else {
      bytes = imageBytes!;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frameInfo = await codec.getNextFrame();
      try {
        if (frameInfo.image.width == 0 || frameInfo.image.height == 0) {
          return null;
        }
        return (width: frameInfo.image.width, height: frameInfo.image.height);
      } finally {
        frameInfo.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (e) {
    _logger.severe("Failed to get image size", e);
    return null;
  }
}
