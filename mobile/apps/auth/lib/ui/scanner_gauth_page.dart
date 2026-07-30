import 'dart:async';
import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/scanner_camera_view.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_import.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_qr_scanner/ente_qr_scanner.dart';
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

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scan)),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: ScannerCameraView(
              overlay: EnteQrScannerOverlay(
                borderColor: getEnteColorScheme(context).primary700,
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
        showToastAboveBottomControls(context, context.l10n.invalidQRCode);
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
    showToastAboveBottomControls(context, "${context.l10n.error} $error");
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
