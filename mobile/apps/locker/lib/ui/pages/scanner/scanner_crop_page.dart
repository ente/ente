import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scan_session_controller.dart';
import 'package:locker/services/scanner/scanner_models.dart';

class ScannerCropPage extends StatefulWidget {
  const ScannerCropPage({
    super.key,
    required this.session,
    required this.pageId,
  });

  final ScanSessionController session;
  final String pageId;

  @override
  State<ScannerCropPage> createState() => _ScannerCropPageState();
}

class _ScannerCropPageState extends State<ScannerCropPage> {
  static const double _handleRadius = 22;

  static const double _minAreaFraction = 0.01;

  static const double _loupeSize = 116;
  static const double _loupeLift = 104;
  static const double _loupeMagnification = 2.0;

  Uint8List? _sourceBytes;
  double _aspect = 3 / 4;
  List<Offset> _corners = const [];
  int _dragging = -1;
  Offset? _dragFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final page = _page;
    if (page == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bytes = await page.sourceJpeg.readAsBytes();
    if (!mounted) return;
    setState(() {
      _sourceBytes = bytes;
      _aspect = page.sourceWidth / page.sourceHeight;
      _corners = [...page.quad.corners];
    });
  }

  ScannedPage? get _page {
    for (final page in widget.session.pages) {
      if (page.id == widget.pageId) return page;
    }
    return null;
  }

  ScanQuad get _orderedQuad => orderClockwise(_corners);

  bool get _canSave =>
      _corners.length == 4 &&
      isUsableQuad(_orderedQuad.corners, minAreaFraction: _minAreaFraction);

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final quad = _orderedQuad;
    await widget.session.updatePage(widget.pageId, quad: quad);
    if (mounted) navigator.pop();
  }

  void _endDrag() {
    if (_dragging < 0 && _dragFocus == null) return;
    setState(() {
      _dragging = -1;
      _dragFocus = null;
    });
  }

  Widget _buildLoupe(Size container, Offset focus, Color color) {
    final above = focus.dy - _loupeLift - _loupeSize / 2 > 0;
    final centerY = above ? focus.dy - _loupeLift : focus.dy + _loupeLift;
    final centerX = focus.dx.clamp(
      _loupeSize / 2,
      container.width - _loupeSize / 2,
    );
    final center = Offset(centerX, centerY);
    return Positioned(
      left: center.dx - _loupeSize / 2,
      top: center.dy - _loupeSize / 2,
      child: RawMagnifier(
        size: const Size(_loupeSize, _loupeSize),
        magnificationScale: _loupeMagnification,
        focalPointOffset: focus - center,
        decoration: MagnifierDecoration(
          shape: const CircleBorder(),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
            ),
          ],
        ),
        child: CustomPaint(painter: _LoupePainter(color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final source = _sourceBytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  IconButtonComponent(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: colors.specialWhite,
                    ),
                    variant: IconButtonComponentVariant.unfilled,
                    onTap: () => Navigator.of(context).pop(),
                    tooltip: context.strings.cancel,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        context.strings.adjustCrop,
                        style: TextStyles.body.copyWith(
                          color: colors.specialWhite,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox.square(dimension: 44),
                ],
              ),
            ),
            Expanded(
              child: source == null
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.specialWhite,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final container = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final rect = fittedRect(container, _aspect);

                          Offset toScreen(Offset normalized) => Offset(
                            rect.left + normalized.dx * rect.width,
                            rect.top + normalized.dy * rect.height,
                          );

                          Offset toNormalized(Offset screen) => Offset(
                            ((screen.dx - rect.left) / rect.width).clamp(
                              0.0,
                              1.0,
                            ),
                            ((screen.dy - rect.top) / rect.height).clamp(
                              0.0,
                              1.0,
                            ),
                          );

                          return GestureDetector(
                            onPanStart: (details) {
                              var best = -1;
                              var bestDistance = double.infinity;
                              for (var i = 0; i < _corners.length; i++) {
                                final distance =
                                    (toScreen(_corners[i]) -
                                            details.localPosition)
                                        .distance;
                                if (distance < bestDistance) {
                                  bestDistance = distance;
                                  best = i;
                                }
                              }
                              final grabbed = bestDistance <= _handleRadius * 2
                                  ? best
                                  : -1;
                              if (grabbed < 0) return;
                              unawaited(HapticFeedback.selectionClick());
                              setState(() {
                                _dragging = grabbed;
                                _dragFocus = toScreen(_corners[grabbed]);
                              });
                            },
                            onPanUpdate: (details) {
                              if (_dragging < 0) return;
                              final normalized = toNormalized(
                                details.localPosition,
                              );
                              setState(() {
                                final updated = [..._corners];
                                updated[_dragging] = normalized;
                                _corners = updated;
                                _dragFocus = toScreen(normalized);
                              });
                            },
                            onPanEnd: (_) => _endDrag(),
                            onPanCancel: _endDrag,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fromRect(
                                  rect: rect,
                                  child: Image.memory(source, fit: BoxFit.fill),
                                ),
                                CustomPaint(
                                  painter: _CropPainter(
                                    corners: [
                                      for (final c in _corners) toScreen(c),
                                    ],
                                    color: colors.primary,
                                    activeIndex: _dragging,
                                  ),
                                ),
                                if (_dragging >= 0 && _dragFocus != null)
                                  _buildLoupe(
                                    container,
                                    _dragFocus!,
                                    colors.primary,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: ButtonComponent(
                label: context.strings.save,
                onTap: source == null || !_canSave ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.corners,
    required this.color,
    required this.activeIndex,
  });

  final List<Offset> corners;
  final Color color;
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = 0; i < corners.length; i++) {
      final corner = corners[i];
      final radius = i == activeIndex ? 5.0 : 12.0;
      canvas.drawCircle(
        corner,
        radius,
        Paint()..color = color.withValues(alpha: 0.45),
      );
      canvas.drawCircle(
        corner,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.color != color ||
      oldDelegate.activeIndex != activeIndex;
}

class _LoupePainter extends CustomPainter {
  const _LoupePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const gap = 6.0;
    const arm = 14.0;
    canvas
      ..drawLine(
        center - const Offset(arm, 0),
        center - const Offset(gap, 0),
        paint,
      )
      ..drawLine(
        center + const Offset(gap, 0),
        center + const Offset(arm, 0),
        paint,
      )
      ..drawLine(
        center - const Offset(0, arm),
        center - const Offset(0, gap),
        paint,
      )
      ..drawLine(
        center + const Offset(0, gap),
        center + const Offset(0, arm),
        paint,
      )
      ..drawCircle(
        center,
        size.width / 2 - 1.5,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_LoupePainter oldDelegate) => oldDelegate.color != color;
}
