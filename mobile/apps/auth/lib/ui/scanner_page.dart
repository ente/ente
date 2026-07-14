import 'dart:async';
import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/buttons/icon_button_widget.dart';
import 'package:ente_auth/ui/components/scanner_camera_view.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_import.dart';
import 'package:ente_auth/utils/gallery_import_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_qr_scanner/ente_qr_scanner.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class ScannerPageResult {
  final Code? code;
  final bool fromGallery;
  final List<Code>? googleAuthCodes;

  const ScannerPageResult.single({
    required Code this.code,
    required this.fromGallery,
  }) : googleAuthCodes = null;

  int get importedCodeCount => googleAuthCodes?.length ?? 0;

  const ScannerPageResult.googleAuthCodes(this.googleAuthCodes)
    : code = null,
      fromGallery = false;
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => ScannerPageState();
}

class ScannerPageState extends State<ScannerPage> {
  final Logger _logger = Logger('ScannerPage');
  EnteQrScannerController? controller;
  StreamSubscription<String>? _scanSubscription;
  bool _isImportingFromGallery = false;
  bool _hasCompletedScan = false;
  bool _isHandlingGoogleAuthImport = false;
  bool _isTogglingFlash = false;
  bool? _isFlashOn;

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
    final bool showGalleryImport = PlatformDetector.isMobile();
    final bool showTorch = showGalleryImport && _isFlashOn != null;
    final bool isFlashOn = _isFlashOn == true;
    final theme = Theme.of(context);
    final colorScheme = getEnteColorScheme(context);
    final bool isLight = theme.brightness == Brightness.light;
    final Color actionBackgroundColor = isLight
        ? Colors.black.withValues(alpha: 0.035)
        : Colors.white.withValues(alpha: 0.18);
    final Color actionPressedColor = isLight
        ? Colors.black.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.26);
    final Color actionIconColor = isLight ? Colors.black : Colors.white;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scan)),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: ScannerCameraView(
              overlay: EnteQrScannerOverlay(
                borderColor: colorScheme.primary700,
                cutOutSize: 260,
                overlayColor: Colors.black.withValues(alpha: 0.45),
              ),
              onScannerCreated: _onScannerCreated,
              onError: _handleScannerError,
            ),
          ),
          Expanded(
            flex: 1,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: showGalleryImport
                      ? Row(
                          children: [
                            const Spacer(),
                            if (showTorch)
                              _scannerActionButton(
                                label: isFlashOn
                                    ? l10n.scannerTorchOff
                                    : l10n.scannerTorchOn,
                                icon: isFlashOn
                                    ? Icons.flashlight_on_outlined
                                    : Icons.flashlight_off_outlined,
                                onTap: _isTogglingFlash ? null : _toggleFlash,
                                disabled: _isTogglingFlash,
                                defaultColor: isFlashOn
                                    ? colorScheme.primary700
                                    : actionBackgroundColor,
                                pressedColor: isFlashOn
                                    ? colorScheme.primary500
                                    : actionPressedColor,
                                iconColor: isFlashOn
                                    ? Colors.white
                                    : actionIconColor,
                              ),
                            _scannerActionButton(
                              label: l10n.importFromGallery,
                              icon: Icons.photo_library_outlined,
                              onTap: _isImportingFromGallery
                                  ? null
                                  : _handleImportFromGallery,
                              disabled: _isImportingFromGallery,
                              defaultColor: actionBackgroundColor,
                              pressedColor: actionPressedColor,
                              iconColor: actionIconColor,
                            ),
                          ],
                        )
                      : Text(
                          l10n.scanACode,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScannerCreated(EnteQrScannerController controller) {
    this.controller = controller;
    controller.onTorchStatusChanged = _updateFlashStatus;
    _cancelScanSubscription();
    _scanSubscription = controller.codes.listen(_handleScanData);
    unawaited(_refreshFlashStatus());
  }

  void _handleScannerError(String message) {
    _logger.warning('Scanner error: $message');
  }

  Widget _scannerActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool disabled,
    required Color defaultColor,
    required Color pressedColor,
    required Color iconColor,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButtonWidget(
            icon: icon,
            iconButtonType: IconButtonType.rounded,
            onTap: onTap,
            defaultColor: defaultColor,
            iconColor: iconColor,
            pressedColor: pressedColor,
            size: 28,
            padding: const EdgeInsets.all(14),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshFlashStatus() async {
    if (!PlatformDetector.isMobile()) {
      return;
    }
    try {
      final flashStatus = await controller?.getTorchStatus();
      if (!mounted) {
        return;
      }
      _updateFlashStatus(flashStatus);
    } catch (e, s) {
      _logger.warning('Failed to get scanner torch status', e, s);
      if (mounted) {
        _updateFlashStatus(null);
      }
    }
  }

  void _updateFlashStatus(bool? isFlashOn) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isFlashOn = isFlashOn;
    });
  }

  Future<void> _toggleFlash() async {
    if (_isTogglingFlash || _isFlashOn == null) {
      return;
    }
    setState(() {
      _isTogglingFlash = true;
    });
    try {
      await controller?.toggleTorch();
      await _refreshFlashStatus();
    } catch (e, s) {
      _logger.warning('Failed to toggle scanner torch', e, s);
      await _refreshFlashStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFlash = false;
        });
      } else {
        _isTogglingFlash = false;
      }
    }
  }

  void _handleScanData(String qrCode) {
    if (_hasCompletedScan || _isImportingFromGallery) {
      return;
    }

    if (isGoogleAuthExportQr(qrCode)) {
      unawaited(_handleGoogleAuthImport(qrCode));
      return;
    }

    try {
      final code = Code.fromOTPAuthUrl(qrCode);
      _completeWithResult(
        ScannerPageResult.single(code: code, fromGallery: false),
      );
    } catch (e) {
      if (mounted) {
        showToastAboveBottomControls(context, context.l10n.invalidQRCode);
      }
    }
  }

  Future<void> _handleGoogleAuthImport(String qrCode) async {
    if (_hasCompletedScan || _isHandlingGoogleAuthImport) {
      return;
    }
    _isHandlingGoogleAuthImport = true;
    bool shouldResumeCamera = true;
    try {
      await controller?.pause();
      final codes = parseGoogleAuth(qrCode);
      if (codes.isEmpty) {
        if (mounted) {
          showToastAboveBottomControls(context, context.l10n.invalidQRCode);
        }
        return;
      }
      if (!mounted || _hasCompletedScan) {
        return;
      }
      final shouldImport = await confirmGoogleAuthImport(context, codes.length);
      if (!shouldImport || !mounted || _hasCompletedScan) {
        return;
      }
      shouldResumeCamera = false;
      _completeWithResult(ScannerPageResult.googleAuthCodes(codes));
    } catch (e, s) {
      _logger.severe("Error importing Google Authenticator QR", e, s);
      if (mounted) {
        showToastAboveBottomControls(context, context.l10n.invalidQRCode);
      }
    } finally {
      if (shouldResumeCamera && mounted && !_hasCompletedScan) {
        await controller?.resume();
      }
      _isHandlingGoogleAuthImport = false;
    }
  }

  Future<void> _handleImportFromGallery() async {
    if (_isImportingFromGallery || _hasCompletedScan) {
      return;
    }
    setState(() {
      _isImportingFromGallery = true;
    });
    bool shouldResumeCamera = true;
    try {
      if (!mounted) return;
      await controller?.pause();
      if (!mounted) return;
      final GalleryImportResult? importResult = await pickCodeFromGallery(
        context,
        logger: _logger,
      );
      if (importResult == null) {
        return;
      }
      final googleAuthCodes = importResult.googleAuthCodes;
      if (googleAuthCodes != null) {
        if (!mounted) return;
        final shouldImport = await confirmGoogleAuthImport(
          context,
          googleAuthCodes.length,
        );
        if (!shouldImport || !mounted || _hasCompletedScan) {
          return;
        }
        shouldResumeCamera = false;
        _completeWithResult(ScannerPageResult.googleAuthCodes(googleAuthCodes));
        return;
      }
      final code = importResult.code;
      if (code == null) {
        return;
      }
      shouldResumeCamera = false;
      _completeWithResult(
        ScannerPageResult.single(code: code, fromGallery: true),
      );
    } finally {
      if (shouldResumeCamera && mounted && !_hasCompletedScan) {
        await controller?.resume();
      }
      if (mounted && !_hasCompletedScan) {
        setState(() {
          _isImportingFromGallery = false;
        });
      } else {
        _isImportingFromGallery = false;
      }
    }
  }

  void _completeWithResult(ScannerPageResult result) {
    if (_hasCompletedScan) {
      return;
    }
    _hasCompletedScan = true;
    _cancelScanSubscription();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
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
