import "dart:async";
import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";

typedef RewindBytes =
    Future<Uint8List?> Function(EnteFile file, {bool cachedOnly});

typedef RewindPhotoBuilder =
    Widget Function(EnteFile file, {ui.Image? decoded});

Widget rewindPhoto(EnteFile file, {ui.Image? decoded}) =>
    RewindPhoto(file, decoded: decoded);

typedef RewindTilePainter =
    void Function(Canvas canvas, ui.Image image, Rect cell, int index);

Future<Uint8List?> rewindThumbnailBytes(
  EnteFile file, {
  bool cachedOnly = false,
}) async {
  if (!cachedOnly || !file.isRemoteOnlyFile) return getThumbnail(file);
  final cached = cachedThumbnailPath(file);
  return await cached.exists() ? cached.readAsBytes() : null;
}

class RewindAtlas {
  RewindAtlas._(this.image, this.tile, this.columns, this.files);

  static const _workers = 4;
  static const _batch = 48;
  static const _breather = Duration(milliseconds: 24);
  static const _patience = Duration(seconds: 8);
  static const _grace = Duration(milliseconds: 60);
  static const _mostUnfinished = 200;
  static final _unfinished = <int>{};
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
    var stalled = false;
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
          final data = await _fetch(
            files[index],
            bytes,
            stalled,
            () => stalled = true,
          );
          if (data != null) {
            images[index - start] = await _decode(data, decodeSide ?? tile);
          }
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

  static Future<Uint8List?> _fetch(
    EnteFile file,
    RewindBytes bytes,
    bool stalled,
    void Function() onStall,
  ) async {
    final remote = file.isRemoteOnlyFile ? file.uploadedFileID : null;
    final cachedOnly = _unfinished.length >= _mostUnfinished;
    final request = bytes(file, cachedOnly: cachedOnly);
    final hurried = remote != null && stalled && !cachedOnly;
    try {
      return await request.timeout(hurried ? _grace : _patience);
    } on TimeoutException {
      if (remote != null && !cachedOnly) {
        onStall();
        _unfinished.add(remote);
        unawaited(
          request
              .then<void>((_) {}, onError: (_) {})
              .whenComplete(() => _unfinished.remove(remote)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _decode(
    Uint8List data,
    int side, {
    bool enlarge = true,
  }) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final fit = side / min(descriptor.width, descriptor.height);
      final scale = enlarge ? fit : min(1.0, fit);
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
  T? _loaded;
  var _generation = 0;
  var _holders = 0;

  Future<T?> get value => _pending ??= _guarded(_generation);

  T? get loaded => _loaded;

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
    return _loaded = loaded;
  }

  void hold() => _holders++;

  void drop() => _holders--;

  void release() {
    if (_holders > 0) return;
    final pending = _pending;
    _pending = null;
    _loaded = null;
    _generation++;
    unawaited(
      pending?.then((loaded) {
        if (loaded != null) _dispose(loaded);
      }),
    );
  }
}

class RewindDecoded {
  RewindDecoded._(this._images);

  final Map<EnteFile, ui.Image> _images;

  ui.Image? operator [](EnteFile photo) => _images[photo];

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
  }

  static RewindWarm<RewindDecoded> warm(
    List<EnteFile> photos,
    RewindBytes bytes,
  ) => RewindWarm(() => _load(photos, bytes), (decoded) => decoded.dispose());

  static Future<RewindDecoded?> _load(
    List<EnteFile> photos,
    RewindBytes bytes,
  ) async {
    final images = await Future.wait([
      for (final photo in photos) _image(photo, bytes),
    ]);
    if (images.contains(null)) {
      for (final image in images) {
        image?.dispose();
      }
      return null;
    }
    return RewindDecoded._(
      Map.identity()..addEntries([
        for (final (index, photo) in photos.indexed)
          MapEntry(photo, images[index]!),
      ]),
    );
  }

  static Future<ui.Image?> _image(EnteFile photo, RewindBytes bytes) async {
    try {
      final data = await bytes(photo).timeout(RewindAtlas._patience);
      if (data == null) return null;
      return await RewindAtlas._decode(
        data,
        thumbnailLargeSize,
        enlarge: false,
      );
    } catch (_) {
      return null;
    }
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
  static const _retryAfterSeconds = [3, 6, 12, 24, 48];

  late T? _value = widget.warm.loaded;

  @override
  void initState() {
    super.initState();
    widget.warm.hold();
    if (_value == null) unawaited(_await());
  }

  @override
  void dispose() {
    widget.warm.drop();
    super.dispose();
  }

  Future<void> _await() async {
    for (var attempt = 0; mounted; attempt++) {
      final value = await widget.warm.value;
      if (!mounted) return;
      if (value != null) {
        setState(() => _value = value);
        return;
      }
      final wait = min(attempt, _retryAfterSeconds.length - 1);
      await Future<void>.delayed(Duration(seconds: _retryAfterSeconds[wait]));
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
