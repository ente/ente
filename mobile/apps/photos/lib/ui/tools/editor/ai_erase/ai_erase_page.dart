import "dart:async";
import "dart:io";
import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart" as ente;
import "package:photos/models/location/location.dart";
import "package:photos/services/machine_learning/inpaint/moebius_models.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/src/rust/api/inpaint_api.dart"
    show InpaintImageRequest, RustInpaintModelPaths, inpaintImageRust;
import "package:photos/src/rust/api/ml_indexing_api.dart"
    show RustExecutionProviderPolicy;
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart"
    show ButtonAction;
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/utils/dialog_util.dart";

/// A single freehand brush stroke. Points are normalised to the source image
/// (0..1 in both axes); [radiusNorm] is a fraction of the image width so the
/// brush stays the same physical size regardless of aspect ratio.
class _Stroke {
  final List<Offset> points;
  final double radiusNorm;
  _Stroke(this.radiusNorm) : points = <Offset>[];
}

/// "AI edit" object-removal screen: the user highlights a region to remove and
/// the Moebius inpainting model (run entirely in Rust) fills it in.
class AiErasePage extends StatefulWidget {
  final ente.EnteFile originalFile;
  final File file;
  final DetailPageConfiguration detailPageConfig;

  const AiErasePage({
    super.key,
    required this.originalFile,
    required this.file,
    required this.detailPageConfig,
  });

  @override
  State<AiErasePage> createState() => _AiErasePageState();
}

class _AiErasePageState extends State<AiErasePage> {
  final _logger = Logger("AiErasePage");

  ui.Image? _image;
  final List<_Stroke> _strokes = [];
  double _brushNorm = 0.05;
  Rect _destRect = Rect.zero;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() => _image = image);
    } catch (e, s) {
      _logger.severe("Failed to load image for AI edit", e, s);
      if (mounted) {
        showToast(context, AppLocalizations.of(context).aiEditFailed);
        _close();
      }
    }
  }

  void _close() {
    replacePage(context, DetailPage(widget.detailPageConfig));
  }

  Offset _toNorm(Offset local) {
    if (_destRect.width == 0 || _destRect.height == 0) return Offset.zero;
    return Offset(
      ((local.dx - _destRect.left) / _destRect.width).clamp(0.0, 1.0),
      ((local.dy - _destRect.top) / _destRect.height).clamp(0.0, 1.0),
    );
  }

  void _onPanStart(DragStartDetails d) {
    if (_running) return;
    final stroke = _Stroke(_brushNorm)..points.add(_toNorm(d.localPosition));
    setState(() => _strokes.add(stroke));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_running || _strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(_toNorm(d.localPosition)));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    setState(_strokes.clear);
  }

  // ── Erase flow ─────────────────────────────────────────────────────────────

  Future<void> _runErase() async {
    final l10n = AppLocalizations.of(context);
    if (_strokes.isEmpty || _image == null) {
      showShortToast(context, l10n.selectAreaToEraseFirst);
      return;
    }

    final modelPaths = await _ensureModels();
    if (modelPaths == null || !mounted) return;

    final dialog = createProgressDialog(context, l10n.erasingPleaseWait);
    await dialog.show();
    setState(() => _running = true);
    String? maskPath;
    try {
      maskPath = await _buildMaskFile(_image!);
      final result = await inpaintImageRust(
        req: InpaintImageRequest(
          imagePath: widget.file.path,
          maskPath: maskPath,
          modelPaths: modelPaths,
          // Plain CPU EP (multithreaded on the Rust side). XNNPACK must stay
          // off: it computes measurably wrong output on the fp16 U-Net
          // (max|delta| ~4.4 vs the fp32 reference, i.e. garbage), gives no
          // speedup on this graph, and ORT rc.4 cannot extract its outputs
          // ("Unknown allocation device"). NNAPI stays off: deprecated since
          // Android 15 and partitions the diffusion graph poorly.
          providerPolicy: const RustExecutionProviderPolicy(
            preferCoreml: false,
            preferNnapi: false,
            preferXnnpack: false,
            allowCpuFallback: true,
          ),
          numSteps: 0, // 0 => pipeline default (20)
          guidance: 0, // 0 => pipeline default (2.0)
          seed: BigInt.from(42),
        ),
      );
      await dialog.hide();
      if (!mounted) return;
      await _saveResult(result);
    } catch (e, s) {
      _logger.severe("AI erase failed", e, s);
      await dialog.hide();
      if (mounted) showToast(context, l10n.aiEditFailed);
    } finally {
      if (mounted) setState(() => _running = false);
      if (maskPath != null) {
        unawaited(File(maskPath).delete().then((_) {}, onError: (_) {}));
      }
    }
  }

  /// Ensures the three Moebius graphs are present, prompting for the one-time
  /// download if needed. Returns null if the user declines or it fails.
  Future<RustInpaintModelPaths?> _ensureModels() async {
    final l10n = AppLocalizations.of(context);
    if (await MoebiusModels.isDownloaded()) {
      return MoebiusModels.ensureDownloaded();
    }
    if (!mounted) return null;
    final choice = await showChoiceDialog(
      context,
      title: l10n.downloadAiModelTitle,
      body: l10n.downloadAiModelMessage,
      firstButtonLabel: l10n.download,
      secondButtonLabel: l10n.cancel,
    );
    if (choice?.action != ButtonAction.first || !mounted) return null;

    final dialog = createProgressDialog(context, l10n.downloadingAiModel);
    await dialog.show();
    final received = <String, int>{};
    final sub = RemoteAssetsService.instance.progressStream.listen((event) {
      final url = event.$1;
      final got = event.$2;
      if (!MoebiusModels.urls.contains(url)) return;
      received[url] = got;
      final sum = received.values.fold<int>(0, (a, b) => a + b);
      final pct = (sum / MoebiusModels.approxTotalBytes * 100).clamp(
        0.0,
        100.0,
      );
      dialog.update(message: "${l10n.downloadingAiModel} ${pct.round()}%");
    });
    try {
      return await MoebiusModels.ensureDownloaded();
    } catch (e, s) {
      _logger.severe("Failed to download AI editing model", e, s);
      if (mounted) showToast(context, l10n.aiEditFailed);
      return null;
    } finally {
      await sub.cancel();
      await dialog.hide();
    }
  }

  /// Rasterises the strokes into a binary mask PNG (white = erase, on black) at
  /// the source image's native resolution and writes it to a temp file.
  Future<String> _buildMaskFile(ui.Image image) async {
    final w = image.width;
    final h = image.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    final fill = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final s in _strokes) {
      final radius = s.radiusNorm * w;
      if (s.points.length == 1) {
        final point = Offset(s.points.first.dx * w, s.points.first.dy * h);
        canvas.drawCircle(point, radius, fill);
      } else {
        stroke.strokeWidth = radius * 2;
        final path = Path()
          ..moveTo(s.points.first.dx * w, s.points.first.dy * h);
        for (final pt in s.points.skip(1)) {
          path.lineTo(pt.dx * w, pt.dy * h);
        }
        canvas.drawPath(path, stroke);
      }
    }

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(w, h);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final file = File(
      "${dir.path}/ai_erase_mask_${DateTime.now().microsecondsSinceEpoch}.png",
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Saves the inpainted JPEG bytes as a new gallery asset and returns to the
  /// viewer, mirroring the regular image editor's save flow.
  Future<void> _saveResult(Uint8List bytes) async {
    final l10n = AppLocalizations.of(context);
    final dialog = createProgressDialog(context, l10n.saving);
    await dialog.show();
    bool hasStoppedChangeNotify = false;
    try {
      final fileName =
          "${p.basenameWithoutExtension(widget.originalFile.title!)}"
          "_edited_${DateTime.now().microsecondsSinceEpoch}.JPEG";
      await PhotoManager.stopChangeNotify();
      hasStoppedChangeNotify = true;
      final AssetEntity newAsset = await PhotoManager.editor.saveImage(
        bytes,
        filename: fileName,
      );
      final newFile = await ente.EnteFile.fromAsset(
        widget.originalFile.deviceFolder ?? '',
        newAsset,
      );
      newFile.creationTime = widget.originalFile.creationTime;
      newFile.collectionID = widget.originalFile.collectionID;
      newFile.location = widget.originalFile.location;
      if (!newFile.hasLocation && widget.originalFile.localID != null) {
        final assetEntity = await widget.originalFile.getAsset;
        if (assetEntity != null) {
          final latLong = await assetEntity.latlngAsync();
          newFile.location = Location(
            latitude: latLong.latitude,
            longitude: latLong.longitude,
          );
        }
      }
      newFile.generatedID = await FilesDB.instance.insertAndGetId(newFile);
      Bus.instance.fire(
        LocalPhotosUpdatedEvent([newFile], source: "aiEditSave"),
      );
      unawaited(SyncService.instance.sync());
      showShortToast(context, l10n.editsSaved);

      final files = widget.detailPageConfig.files;
      int selectionIndex = files.indexWhere(
        (f) => f.generatedID == newFile.generatedID,
      );
      if (selectionIndex == -1) {
        files.add(newFile);
        selectionIndex = files.length - 1;
      }
      await dialog.hide();
      if (!mounted) return;
      replacePage(
        context,
        DetailPage(
          widget.detailPageConfig.copyWith(
            files: files,
            selectedIndex: min(selectionIndex, files.length - 1),
          ),
        ),
      );
    } catch (e, s) {
      await dialog.hide();
      _logger.severe("Failed to save AI edit", e, s);
      if (mounted) showToast(context, l10n.oopsCouldNotSaveEdits);
    } finally {
      if (hasStoppedChangeNotify) {
        await PhotoManager.startChangeNotify();
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final hasStrokes = _strokes.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _running ? null : _close,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.aiEdit,
                    style: textTheme.bodyBold.copyWith(color: Colors.white),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: (_running || !hasStrokes) ? null : _runErase,
                    child: Text(
                      l10n.erase,
                      style: textTheme.bodyBold.copyWith(
                        color: (_running || !hasStrokes)
                            ? colorScheme.textMuted
                            : colorScheme.primary300,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Canvas.
            Expanded(
              child: _image == null
                  ? const EnteLoadingWidget()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final imageSize = Size(
                          _image!.width.toDouble(),
                          _image!.height.toDouble(),
                        );
                        final fitted = applyBoxFit(
                          BoxFit.contain,
                          imageSize,
                          Size(constraints.maxWidth, constraints.maxHeight),
                        );
                        final dest = fitted.destination;
                        _destRect = Rect.fromLTWH(
                          (constraints.maxWidth - dest.width) / 2,
                          (constraints.maxHeight - dest.height) / 2,
                          dest.width,
                          dest.height,
                        );
                        return GestureDetector(
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          child: CustomPaint(
                            size: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                            painter: _MaskPainter(
                              image: _image!,
                              destRect: _destRect,
                              strokes: _strokes,
                              overlayColor: colorScheme.primary500.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Bottom controls.
            _buildControls(colorScheme, textTheme, l10n, hasStrokes),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(
    EnteColorScheme colorScheme,
    EnteTextTheme textTheme,
    AppLocalizations l10n,
    bool hasStrokes,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.brush_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _brushNorm,
                  min: 0.01,
                  max: 0.15,
                  activeColor: colorScheme.primary300,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _brushNorm = v),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: (_running || !hasStrokes) ? null : _undo,
                icon: const Icon(Icons.undo, color: Colors.white),
                label: Text(
                  l10n.undo,
                  style: textTheme.body.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 24),
              TextButton.icon(
                onPressed: (_running || !hasStrokes) ? null : _clear,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                label: Text(
                  l10n.clearAll,
                  style: textTheme.body.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.aiEraseHint,
            textAlign: TextAlign.center,
            style: textTheme.miniMuted,
          ),
        ],
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final ui.Image image;
  final Rect destRect;
  final List<_Stroke> strokes;
  final Color overlayColor;

  _MaskPainter({
    required this.image,
    required this.destRect,
    required this.strokes,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, srcRect, destRect, Paint());

    if (strokes.isEmpty) return;

    // Draw the strokes opaque into a single transparency layer that is then
    // composited at the overlay opacity, so overlapping strokes stay a uniform
    // colour instead of darkening where they overlap.
    canvas.saveLayer(
      destRect,
      Paint()..color = Color.fromRGBO(0, 0, 0, overlayColor.a),
    );
    final opaque = overlayColor.withValues(alpha: 1.0);
    final fill = Paint()
      ..color = opaque
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = opaque
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset toCanvas(Offset norm) => Offset(
      destRect.left + norm.dx * destRect.width,
      destRect.top + norm.dy * destRect.height,
    );

    for (final s in strokes) {
      final radius = s.radiusNorm * destRect.width;
      if (s.points.length == 1) {
        canvas.drawCircle(toCanvas(s.points.first), radius, fill);
      } else {
        stroke.strokeWidth = radius * 2;
        final path = Path()
          ..moveTo(toCanvas(s.points.first).dx, toCanvas(s.points.first).dy);
        for (final pt in s.points.skip(1)) {
          final c = toCanvas(pt);
          path.lineTo(c.dx, c.dy);
        }
        canvas.drawPath(path, stroke);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) => true;
}
