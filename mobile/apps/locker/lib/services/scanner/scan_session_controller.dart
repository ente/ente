import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:locker/services/scanner/document_scanner_service.dart';
import 'package:locker/services/scanner/pdf_writer.dart';
import 'package:locker/services/scanner/scanner_models.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScanSessionController extends ChangeNotifier {
  static const _pdfExtension = '.pdf';

  final _logger = Logger('ScanSessionController');
  final DocumentScannerService _service = DocumentScannerService.instance;
  final List<ScannedPage> _pages = [];
  final List<File> _exports = [];
  Future<void> _queue = Future.value();
  int _pendingCount = 0;
  bool _disposed = false;
  Object? _lastError;
  String? _fileName;

  List<ScannedPage> get pages => List.unmodifiable(_pages);
  int get pageCount => _pages.length;
  int get pendingCount => _pendingCount;
  bool get isProcessing => _pendingCount > 0;

  String? get fileName => _fileName;

  void ensureFileName(String fileName) {
    _fileName ??= fileName;
  }

  void renameFile(String baseName) {
    var cleaned = baseName.replaceAll(RegExp(r'[/\\]'), '').trim();
    if (cleaned.toLowerCase().endsWith(_pdfExtension)) {
      cleaned = cleaned
          .substring(0, cleaned.length - _pdfExtension.length)
          .trim();
    }
    if (cleaned.isEmpty) return;
    _fileName = '$cleaned$_pdfExtension';
    notifyListeners();
  }

  ScannedPage? get lastPage => _pages.isEmpty ? null : _pages.last;

  Object? takeLastError() {
    final error = _lastError;
    _lastError = null;
    return error;
  }

  Future<void> init() => _service.init();

  bool get isServiceReady => _service.isReady;

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
  }) => _service.detectLiveYuv(
    y: y,
    u: u,
    v: v,
    yRowStride: yRowStride,
    uvRowStride: uvRowStride,
    uvPixelStride: uvPixelStride,
    width: width,
    height: height,
    rotationDegrees: rotationDegrees,
  );

  Future<ScanQuad?> detectLiveBgra(
    Uint8List bytes,
    int rowStride,
    int width,
    int height,
    int rotationDegrees,
  ) =>
      _service.detectLiveBgra(bytes, rowStride, width, height, rotationDegrees);

  void addCapture(Uint8List capturedJpeg) {
    _pendingCount++;
    notifyListeners();
    _queue = _queue.then((_) async {
      try {
        final page = await _service.processCapture(capturedJpeg);
        if (_disposed) {
          await _service.disposePage(page);
          return;
        }
        _pages.add(page);
      } catch (e, s) {
        _logger.severe('Failed to process capture', e, s);
        _lastError = e;
      } finally {
        _pendingCount--;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> waitForPending() async {
    while (_pendingCount > 0) {
      await _queue;
    }
  }

  Future<void> updatePage(
    String pageId, {
    ScanQuad? quad,
    int? rotationDegrees,
  }) async {
    final index = _pages.indexWhere((page) => page.id == pageId);
    if (index < 0) return;
    final updated = await _service.updatePage(
      _pages[index],
      quad: quad,
      rotationDegrees: rotationDegrees,
    );
    if (_disposed) {
      await _service.disposePage(updated);
      return;
    }
    _pages[index] = updated;
    notifyListeners();
  }

  Future<void> rotatePageClockwise(String pageId) async {
    final index = _pages.indexWhere((page) => page.id == pageId);
    if (index < 0) return;
    await updatePage(
      pageId,
      rotationDegrees: (_pages[index].rotationDegrees + 90) % 360,
    );
  }

  void reorderPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, _pages.length - 1);
    if (newIndex == oldIndex) return;
    final page = _pages.removeAt(oldIndex);
    _pages.insert(newIndex, page);
    notifyListeners();
  }

  Future<void> deletePage(String pageId) async {
    final index = _pages.indexWhere((page) => page.id == pageId);
    if (index < 0) return;
    final page = _pages.removeAt(index);
    notifyListeners();
    await _service.disposePage(page);
  }

  Future<File> buildPdf() async {
    final fileName = _fileName;
    if (fileName == null) {
      throw StateError('fileName has not been set');
    }
    final specs = <PdfPageSpec>[];
    for (final page in List.of(_pages)) {
      final jpeg = await page.processedJpeg.readAsBytes();
      final size = _pageSizeMm(page);
      specs.add(
        PdfPageSpec(jpeg: jpeg, widthMm: size.widthMm, heightMm: size.heightMm),
      );
    }
    final bytes = const PdfWriter(creator: 'Ente Locker').build(specs);
    final tmp = await getTemporaryDirectory();
    final dir = await Directory(
      p.join(tmp.path, 'document_scan'),
    ).create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    _exports.add(file);
    return file;
  }

  static ({double widthMm, double heightMm}) _pageSizeMm(ScannedPage page) {
    const a4HeightMm = 297.0;
    final longestPx = page.width > page.height ? page.width : page.height;
    final scale = a4HeightMm / longestPx;
    return constrainToMaxFormat(page.width * scale, page.height * scale);
  }

  Future<void> disposeSession() async {
    if (_disposed) return;
    _disposed = true;
    await waitForPending();
    for (final page in _pages) {
      try {
        await _service.disposePage(page);
      } catch (e) {
        _logger.warning('Failed to dispose page', e);
      }
    }
    _pages.clear();
    for (final file in _exports) {
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        _logger.warning('Failed to delete export', e);
      }
    }
    _exports.clear();
    dispose();
  }
}
