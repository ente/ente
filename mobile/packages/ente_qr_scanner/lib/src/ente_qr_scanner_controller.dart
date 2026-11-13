import 'dart:async';

import 'package:flutter/services.dart';

class EnteQrScannerController {
  EnteQrScannerController(int platformViewId)
    : _channel = MethodChannel('io.ente.qr_scanner/view_$platformViewId') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final StreamController<String> _codesController =
      StreamController<String>.broadcast();
  bool _isDisposed = false;

  void Function(String error)? onError;
  void Function(bool? isOn)? onTorchStatusChanged;

  Stream<String> get codes => _codesController.stream;

  Future<void> pause() => _invokeVoid('pause');

  Future<void> resume() => _invokeVoid('resume');

  Future<bool?> getTorchStatus() async {
    if (_isDisposed) {
      return null;
    }
    return _channel.invokeMethod<bool>('getTorchStatus');
  }

  Future<void> toggleTorch() => _invokeVoid('toggleTorch');

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _channel.setMethodCallHandler(null);
    await _invokeVoid('dispose');
    await _codesController.close();
  }

  Future<void> _invokeVoid(String method) async {
    if (_isDisposed && method != 'dispose') {
      return;
    }
    await _channel.invokeMethod<void>(method);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (_isDisposed) {
      return;
    }
    switch (call.method) {
      case 'onCode':
        final code = call.arguments;
        if (code is String && code.isNotEmpty) {
          _codesController.add(code);
        }
        break;
      case 'onError':
        final error = call.arguments;
        if (error is String && error.isNotEmpty) {
          onError?.call(error);
        }
        break;
      case 'onTorchStatusChanged':
        final status = call.arguments;
        if (status == null || status is bool) {
          onTorchStatusChanged?.call(status as bool?);
        }
        break;
      default:
        throw MissingPluginException(
          'Unknown method ${call.method} on Ente QR scanner channel',
        );
    }
  }
}
