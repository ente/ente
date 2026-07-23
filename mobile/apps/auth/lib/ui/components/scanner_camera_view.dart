import 'package:ente_qr_scanner/ente_qr_scanner.dart';
import 'package:flutter/material.dart';

class ScannerCameraView extends StatefulWidget {
  const ScannerCameraView({
    required this.overlay,
    required this.onScannerCreated,
    this.onError,
    super.key,
  });

  final EnteQrScannerOverlay overlay;
  final ValueChanged<EnteQrScannerController> onScannerCreated;
  final ValueChanged<String>? onError;

  @override
  State<ScannerCameraView> createState() => _ScannerCameraViewState();
}

class _ScannerCameraViewState extends State<ScannerCameraView> {
  @override
  Widget build(BuildContext context) {
    return EnteQrScannerView(
      overlay: widget.overlay,
      onScannerCreated: widget.onScannerCreated,
      onError: widget.onError,
    );
  }
}
