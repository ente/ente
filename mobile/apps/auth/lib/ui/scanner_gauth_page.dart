import 'dart:async';
import 'dart:io';

import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/scanner_camera_view.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_import.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_qr_scanner/ente_qr_scanner.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class ScannerGoogleAuthPage extends StatefulWidget {
  const ScannerGoogleAuthPage({super.key});

  @override
  State<ScannerGoogleAuthPage> createState() => ScannerGoogleAuthPageState();
}

class ScannerGoogleAuthPageState extends State<ScannerGoogleAuthPage> {
  EnteQrScannerController? controller;
  StreamSubscription<String>? _scanSubscription;
  bool _hasCompletedScan = false;

  // Pause the camera on Android and resume it on iOS for hot reload.
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      unawaited(controller?.pause());
    } else if (Platform.isIOS) {
      unawaited(controller?.resume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scan)),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: ScannerCameraView(
              overlay: EnteQrScannerOverlay(
                borderColor: getEnteColorScheme(context).primary700,
                cutOutSize: 320,
                overlayColor: Colors.black.withValues(alpha: 0.45),
              ),
              onScannerCreated: _onScannerCreated,
            ),
          ),
          Expanded(flex: 1, child: Center(child: Text(l10n.scanACode))),
        ],
      ),
    );
  }

  void _onScannerCreated(EnteQrScannerController controller) {
    this.controller = controller;
    _cancelScanSubscription();
    _scanSubscription = controller.codes.listen(_handleScanData);
  }

  void _handleScanData(String qrCode) {
    if (_hasCompletedScan) {
      return;
    }

    if (!qrCode.startsWith(kGoogleAuthExportPrefix)) {
      if (mounted) {
        showToastAboveBottomControls(context, context.strings.invalidQRCode);
      }
      return;
    }

    try {
      final migration = parseGoogleAuthMigration(qrCode);
      _completeWithMigration(migration);
    } catch (e) {
      _completeWithError(e);
    }
  }

  void _completeWithMigration(GoogleAuthMigration migration) {
    if (_hasCompletedScan) {
      return;
    }
    _hasCompletedScan = true;
    _cancelScanSubscription();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(migration);
  }

  void _completeWithError(Object error) {
    if (_hasCompletedScan) {
      return;
    }
    _hasCompletedScan = true;
    _cancelScanSubscription();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showToastAboveBottomControls(context, "${context.strings.error} $error");
  }

  void _cancelScanSubscription() {
    final scanSubscription = _scanSubscription;
    _scanSubscription = null;
    unawaited(scanSubscription?.cancel());
  }

  @override
  void dispose() {
    _cancelScanSubscription();
    super.dispose();
  }
}
