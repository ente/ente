import "dart:async";
import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";

typedef RewindBytes = Future<Uint8List?> Function(EnteFile file);

typedef RewindPhotoBuilder = Widget Function(EnteFile file);

Widget rewindPhoto(EnteFile file) => RewindPhoto(file);

typedef RewindTilePainter =
    void Function(Canvas canvas, ui.Image image, Rect cell, int index);

Future<Uint8List?> rewindThumbnailBytes(EnteFile file) => getThumbnail(file);

class RewindAtlas {
  RewindAtlas._(this.image, this.tile, this.columns, this.files);

  static const _workers = 4;
  static const _batch = 48;
  static const _breather = Duration(milliseconds: 24);
  static const _fetchTimeout = Duration(seconds: 8);
  static const _rushedBudget = Duration(seconds: 6);

  final ui.Image image;
  final double tile;
  final int columns;
  final List<EnteFile> files;

  int get length => files.length;

  Rect source(int index) => Rect.fromLTWH(
    (index % columns) * tile,
    (index ~/ columns) * tile,
    tile,
    tile,
  );

  void dispose() => image.dispose();

  static Future<RewindAtlas?> load(
    List<EnteFile> files, {
    required int tile,
    RewindBytes bytes = rewindThumbnailBytes,
    int? decodeSide,
    RewindTilePainter paint = paintCover,
    int minimum = 1,
    Duration budget = const Duration(seconds: 12),
    bool Function()? isRushed,
  }) async {
    final columns = max(1, sqrt(files.length).ceil());
    final clock = Stopwatch()..start();
    final loaded = <int>[];
    ui.Image? sheet;
    bool isOver() =>
        clock.elapsed >= budget ||
        (loaded.length >= minimum &&
            clock.elapsed >= _rushedBudget &&
            (isRushed?.call() ?? false));
    for (var start = 0; start < files.length && !isOver(); start += _batch) {
      final end = min(files.length, start + _batch);
      final images = List<ui.Image?>.filled(end - start, null);
      var next = start;
      Future<void> worker() async {
        while (next < end && !isOver()) {
          final index = next++;
          images[index - start] = await _decode(
            files[index],
            bytes,
            decodeSide ?? tile,
          );
        }
      }

      await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final earlier = sheet;
      if (earlier != null) canvas.drawImage(earlier, Offset.zero, Paint());
      for (final (offset, image) in images.indexed) {
        if (image == null) continue;
        final slot = loaded.length;
        final cell = Rect.fromLTWH(
          (slot % columns) * tile.toDouble(),
          (slot ~/ columns) * tile.toDouble(),
          tile.toDouble(),
          tile.toDouble(),
        );
        canvas.save();
        canvas.clipRect(cell);
        paint(canvas, image, cell, start + offset);
        canvas.restore();
        loaded.add(start + offset);
      }
      final picture = recorder.endRecording();
      sheet = await picture.toImage(
        columns * tile,
        max(1, (loaded.length / columns).ceil()) * tile,
      );
      picture.dispose();
      earlier?.dispose();
      for (final image in images) {
        image?.dispose();
      }
      await Future<void>.delayed(_breather);
    }
    final atlas = sheet;
    if (atlas == null || loaded.length < minimum) {
      atlas?.dispose();
      return null;
    }
    return RewindAtlas._(atlas, tile.toDouble(), columns, [
      for (final index in loaded) files[index],
    ]);
  }

  static void paintCover(Canvas canvas, ui.Image image, Rect cell, int index) {
    final side = min(image.width, image.height).toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromCenter(
        center: Offset(image.width / 2, image.height / 2),
        width: side,
        height: side,
      ),
      cell,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static Future<ui.Image?> _decode(
    EnteFile file,
    RewindBytes bytes,
    int side,
  ) async {
    try {
      final data = await bytes(file).timeout(_fetchTimeout);
      if (data == null) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = side / min(descriptor.width, descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: max(1, (descriptor.width * scale).round()),
        targetHeight: max(1, (descriptor.height * scale).round()),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<Float32List> quarters() async {
    final quarters = Float32List(length * 12)..fillRange(0, length * 12, 128);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return quarters;
    const step = 2;
    final side = tile.round();
    final half = side ~/ 2;
    for (var index = 0; index < length; index++) {
      for (var quarter = 0; quarter < 4; quarter++) {
        final left = (index % columns) * side + (quarter & 1) * half;
        final top = (index ~/ columns) * side + (quarter >> 1) * half;
        var red = 0;
        var green = 0;
        var blue = 0;
        var samples = 0;
        for (var y = top; y < top + half; y += step) {
          for (var x = left; x < left + half; x += step) {
            final offset = (y * image.width + x) * 4;
            red += data.getUint8(offset);
            green += data.getUint8(offset + 1);
            blue += data.getUint8(offset + 2);
            samples++;
          }
        }
        quarters
          ..[index * 12 + quarter * 3] = red / samples
          ..[index * 12 + quarter * 3 + 1] = green / samples
          ..[index * 12 + quarter * 3 + 2] = blue / samples;
      }
    }
    return quarters;
  }
}

class RewindWarm<T extends Object> {
  RewindWarm(this._load, this._dispose);

  static final _logger = Logger("RewindWarm");

  final Future<T?> Function() _load;
  final void Function(T value) _dispose;
  Future<T?>? _pending;
  var _generation = 0;

  Future<T?> get value => _pending ??= _guarded(_generation);

  Future<T?> _guarded(int generation) async {
    T? loaded;
    try {
      loaded = await _load();
    } catch (error, stackTrace) {
      _logger.warning("A Rewind card failed to warm up", error, stackTrace);
    }
    if (generation != _generation) {
      if (loaded != null) _dispose(loaded);
      return null;
    }
    if (loaded == null) _pending = null;
    return loaded;
  }

  void release() {
    final pending = _pending;
    _pending = null;
    _generation++;
    unawaited(
      pending?.then((loaded) {
        if (loaded != null) _dispose(loaded);
      }),
    );
  }
}

class RewindWarmBuilder<T extends Object> extends StatefulWidget {
  const RewindWarmBuilder({
    required this.warm,
    required this.builder,
    super.key,
  });

  final RewindWarm<T> warm;
  final Widget Function(BuildContext context, T? value) builder;

  @override
  State<RewindWarmBuilder<T>> createState() => _RewindWarmBuilderState<T>();
}

class _RewindWarmBuilderState<T extends Object>
    extends State<RewindWarmBuilder<T>> {
  static const _retryAfter = Duration(seconds: 3);

  T? _value;

  @override
  void initState() {
    super.initState();
    unawaited(_await());
  }

  Future<void> _await() async {
    while (mounted) {
      final value = await widget.warm.value;
      if (!mounted) return;
      if (value != null) {
        setState(() => _value = value);
        return;
      }
      await Future<void>.delayed(_retryAfter);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
