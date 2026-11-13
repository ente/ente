import 'package:flutter/services.dart';

enum WallpaperDestination { home, lock, both }

class WallpaperPreview {
  const WallpaperPreview(this.bytes, this.size);

  final Uint8List bytes;
  final Size size;
}

class WallpaperClient {
  static const _channel = MethodChannel('io.ente.photos.platform/wallpaper');

  Future<WallpaperPreview> prepare() async {
    final result = (await _channel.invokeMapMethod<String, dynamic>(
      'prepare',
    ))!;
    return WallpaperPreview(
      result['bytes'] as Uint8List,
      Size(
        (result['width'] as int).toDouble(),
        (result['height'] as int).toDouble(),
      ),
    );
  }

  Future<void> apply(Rect region, WallpaperDestination destination) {
    return _channel.invokeMethod('apply', {
      'region': [region.left, region.top, region.right, region.bottom],
      'destination': destination.name,
    });
  }
}
