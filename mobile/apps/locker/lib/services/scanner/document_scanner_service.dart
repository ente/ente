import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:locker/services/scanner/scanner_models.dart';
import 'package:locker/src/rust/api/document_scanner_api.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DocumentScannerService {
  DocumentScannerService._();

  static final DocumentScannerService instance = DocumentScannerService._();

  static const int _maxPixels = 4000000;
  static const double _maskSide = 256;

  final _logger = Logger('DocumentScannerService');
  Directory? _dir;
  ScannerSession? _session;
  Future<void>? _initialization;
  int _counter = 0;
  DateTime _lastLiveLog = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() {
    return _initialization ??= () async {
      try {
        await _initialize();
      } catch (_) {
        _initialization = null;
        rethrow;
      }
    }();
  }

  Future<void> _initialize() async {
    final watch = Stopwatch()..start();
    try {
      final tmp = await getTemporaryDirectory();
      _dir = await Directory(
        p.join(tmp.path, 'document_scan'),
      ).create(recursive: true);
      final support = await getApplicationSupportDirectory();
      _session = await ScannerSession.create(
        assetsDir: p.join(support.path, 'assets'),
      );
      _logger.info(
        'Initialized: session ready in ${watch.elapsedMilliseconds}ms',
      );
    } catch (e, s) {
      _logger.severe('Initialization failed', e, s);
      rethrow;
    }
  }

  bool get isReady => _session != null;

  ScannerSession get _readySession {
    final session = _session;
    if (session == null) {
      throw StateError('DocumentScannerService not initialized');
    }
    return session;
  }

  Directory get _root {
    final dir = _dir;
    if (dir == null) {
      throw StateError('DocumentScannerService not initialized');
    }
    return dir;
  }

  Future<ScanQuad?> detectLiveYuv({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int width,
    required int height,
    required int rotationDegrees,
  }) async {
    final session = _session;
    if (session == null) return null;
    try {
      final quad = await session.liveDetectYuv420(
        y: y,
        u: u,
        v: v,
        layout: RustPlaneLayout(
          width: width,
          height: height,
          yRowStride: yRowStride,
          uvRowStride: uvRowStride,
          uvPixelStride: uvPixelStride,
        ),
        rotationDegrees: rotationDegrees,
      );
      return quad == null ? null : _normalized(quad, _maskSide, _maskSide);
    } catch (e) {
      _logLiveThrottled(e);
      return null;
    }
  }

  Future<ScanQuad?> detectLiveBgra(
    Uint8List bytes,
    int rowStride,
    int width,
    int height,
    int rotationDegrees,
  ) async {
    final session = _session;
    if (session == null) return null;
    try {
      final quad = await session.liveDetectBgra(
        bgra: bytes,
        rowStride: rowStride,
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
      );
      return quad == null ? null : _normalized(quad, _maskSide, _maskSide);
    } catch (e) {
      _logLiveThrottled(e);
      return null;
    }
  }

  void _logLiveThrottled(Object error) {
    final now = DateTime.now();
    if (now.difference(_lastLiveLog).inSeconds < 10) return;
    _lastLiveLog = now;
    _logger.warning('Live detection frame failed', error);
  }

  Future<ScannedPage> processCapture(Uint8List capturedJpeg) async {
    try {
      final result = await _readySession.processCapture(
        imageBytes: capturedJpeg,
        maxPixels: _maxPixels,
      );
      final id = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
      final source = File(p.join(_root.path, '${id}_src.jpg'));
      final processed = File(p.join(_root.path, '${id}_r0.jpg'));
      await source.writeAsBytes(capturedJpeg, flush: true);
      await processed.writeAsBytes(result.processedImage, flush: true);
      final quad = result.quad;
      return ScannedPage(
        id: id,
        sourceJpeg: source,
        processedJpeg: processed,
        quad: quad == null
            ? ScanQuad.fullFrame()
            : _normalized(
                quad,
                result.sourceWidth.toDouble(),
                result.sourceHeight.toDouble(),
              ),
        rotationDegrees: 0,
        resolvedColorMode: _colorModeFromRust(result.colorMode),
        sourceWidth: result.sourceWidth,
        sourceHeight: result.sourceHeight,
        width: result.outputWidth,
        height: result.outputHeight,
      );
    } catch (e, s) {
      _logger.severe('processCapture failed', e, s);
      rethrow;
    }
  }

  Future<ScannedPage> updatePage(
    ScannedPage page, {
    ScanQuad? quad,
    int? rotationDegrees,
  }) async {
    try {
      final sourceBytes = await page.sourceJpeg.readAsBytes();
      final result = await _readySession.reprocess(
        sourceBytes: sourceBytes,
        options: RustReprocessOptions(
          quad: _inSourcePixels(
            quad ?? page.quad,
            page.sourceWidth,
            page.sourceHeight,
          ),
          rotationDegrees: rotationDegrees ?? page.rotationDegrees,
          colorMode: _colorModeToRust(page.resolvedColorMode),
          maxPixels: _maxPixels,
        ),
      );
      final processed = File(
        p.join(_root.path, '${page.id}_r${++_counter}.jpg'),
      );
      await processed.writeAsBytes(result.processedImage, flush: true);
      if (page.processedJpeg.path != processed.path) {
        await _deleteIfExists(page.processedJpeg);
      }
      return page.copyWith(
        processedJpeg: processed,
        quad: quad,
        rotationDegrees: rotationDegrees,
        width: result.outputWidth,
        height: result.outputHeight,
      );
    } catch (e, s) {
      _logger.severe('updatePage failed', e, s);
      rethrow;
    }
  }

  Future<void> disposePage(ScannedPage page) async {
    await _deleteIfExists(page.sourceJpeg);
    await _deleteIfExists(page.processedJpeg);
  }

  Future<void> dispose() async {
    _session?.dispose();
    _session = null;
    _initialization = null;
    _dir = null;
  }

  static ScanQuad _normalized(RustQuad quad, double width, double height) {
    Offset scale(RustPoint point) => Offset(point.x / width, point.y / height);
    return ScanQuad([
      scale(quad.topLeft),
      scale(quad.topRight),
      scale(quad.bottomRight),
      scale(quad.bottomLeft),
    ]);
  }

  static RustQuad _inSourcePixels(ScanQuad quad, int width, int height) {
    RustPoint scale(Offset corner) =>
        RustPoint(x: corner.dx * width, y: corner.dy * height);
    return RustQuad(
      topLeft: scale(quad.corners[0]),
      topRight: scale(quad.corners[1]),
      bottomRight: scale(quad.corners[2]),
      bottomLeft: scale(quad.corners[3]),
    );
  }

  static ScanColorMode _colorModeFromRust(RustColorMode mode) => switch (mode) {
    RustColorMode.color => ScanColorMode.color,
    RustColorMode.grayscale => ScanColorMode.grayscale,
  };

  static RustColorMode _colorModeToRust(ScanColorMode mode) => switch (mode) {
    ScanColorMode.grayscale => RustColorMode.grayscale,
    ScanColorMode.color => RustColorMode.color,
  };

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
