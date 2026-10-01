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

  ValueListenable<double> get progress => _progress;

  Future<void> export({
    required List<String> inputPaths,
    required String outputPath,
  }) => _channel.invokeMethod<void>('memoriesExport.export', {
    'inputPaths': inputPaths,
    'outputPath': outputPath,
  });

  Future<void> cancel() => _channel.invokeMethod<void>('memoriesExport.cancel');
}
