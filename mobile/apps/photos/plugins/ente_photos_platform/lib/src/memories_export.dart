import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MemoriesExportClient {
  MemoriesExportClient._() {
    _channel.setMethodCallHandler((call) async {
      _progress.value = call.arguments as double;
    });
  }

  static final instance = MemoriesExportClient._();
  static const _channel = MethodChannel(
    'io.ente.photos.platform/memories_export',
  );

  final _progress = ValueNotifier<double>(0.0);
  Completer<void>? _exportStopped;
  bool _cancelRequested = false;

  ValueListenable<double> get progress => _progress;

  Future<void> export({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    if (_exportStopped != null) {
      throw PlatformException(
        code: 'export_in_progress',
        message: 'An export is already running',
      );
    }

    final stopped = Completer<void>();
    _exportStopped = stopped;
    _cancelRequested = false;
    try {
      try {
        final work = _channel.invokeMethod<void>('memoriesExport.export', {
          'inputPaths': inputPaths,
          'outputPath': outputPath,
        });
        _progress.value = 0.0;
        await work;
      } catch (_) {
        if (!_cancelRequested) rethrow;
      }
      if (_cancelRequested) {
        throw PlatformException(
          code: 'export_cancelled',
          message: 'Export cancelled',
        );
      }
      _progress.value = 1.0;
    } finally {
      _exportStopped = null;
      stopped.complete();
    }
  }

  Future<void> cancel() async {
    final stopped = _exportStopped;
    if (stopped == null) return;
    if (!_cancelRequested) {
      _cancelRequested = true;
      try {
        await _channel.invokeMethod<void>('memoriesExport.cancel');
      } catch (_) {
        if (_exportStopped == stopped) {
          _cancelRequested = false;
        }
        rethrow;
      }
    }
    await stopped.future;
  }
}
