import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:pdfx/pdfx.dart' as pdf;

enum _ViewerAction { download, openExternally }

typedef _RenderedPdfPage = ({MemoryImage image, double aspectRatio});

class DocumentViewerPage extends StatefulWidget {
  const DocumentViewerPage({
    super.key,
    required this.localFile,
    required this.fileName,
    required this.isPdf,
    required this.onOpenExternally,
    this.openPdf = pdf.PdfDocument.openFile,
    this.onDownload,
    this.onShare,
  });

  final File localFile;
  final String fileName;
  final bool isPdf;
  final Future<void> Function(BuildContext) onOpenExternally;
  final Future<pdf.PdfDocument> Function(String) openPdf;
  final Future<void> Function(BuildContext)? onDownload;
  final Future<void> Function(BuildContext)? onShare;

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  static final _logger = Logger('DocumentViewerPage');
  static const _maxImageDimension = 3072;
  final _transformation = TransformationController();
  final _pdfTransformation = TransformationController();
  final _pdfContentKey = GlobalKey();
  final _pdfPage = ValueNotifier(1);
  final _pageAspectRatios = <int, double>{};
  List<double> _pdfPageOffsets = [];
  Size _pdfViewport = Size.zero;
  pdf.PdfDocument? _document;
  Future<void>? _pendingRender;
  ImageProvider? _image;
  bool _loading = false;
  bool _failed = false;
  Completer<void>? _pdfInteraction;
  int _pdfLayoutRevision = 0;
  bool _toolbarVisible = true;

  double get _toolbarHeight => math.max(
    kToolbarHeight,
    MediaQuery.textScalerOf(context).scale(20) * 1.4,
  );

  void _setToolbarVisible(bool visible) {
    if (_toolbarVisible == visible ||
        _loading ||
        _failed ||
        MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    setState(() => _toolbarVisible = visible);
  }

  void _onZoom(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 && (details.scale - 1).abs() > 0.01) {
      _setToolbarVisible(false);
    }
  }

  PreferredSizeWidget _overlayToolbar(AppBar toolbar) {
    final visible =
        _toolbarVisible ||
        _loading ||
        _failed ||
        MediaQuery.accessibleNavigationOf(context);
    return PreferredSize(
      preferredSize: toolbar.preferredSize,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: toolbar,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) {
      _pdfTransformation.addListener(_updatePdfPage);
      _loading = true;
      _pendingRender = _openDocument();
    } else {
      _image = ResizeImage(
        FileImage(widget.localFile),
        width: _maxImageDimension,
        height: _maxImageDimension,
        policy: ResizeImagePolicy.fit,
      );
    }
  }

  Future<void> _openDocument() async {
    try {
      _document = await widget.openPdf(widget.localFile.path);
      if (_document!.pagesCount < 1) throw StateError('PDF has no pages');
      if (mounted) setState(() => _loading = false);
    } catch (error, stack) {
      _logger.warning('Failed to open PDF document', error, stack);
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<_RenderedPdfPage?> _renderPage(int number, bool Function() isActive) {
    // Android permits only one open native page per document at a time.
    final result = _pendingRender!.then<_RenderedPdfPage?>((_) async {
      if (!mounted || !isActive()) return null;
      final page = await _document!.getPage(number);
      try {
        if (!mounted || !isActive()) return null;
        final scale = _maxImageDimension / math.max(page.width, page.height);
        final rendered = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdf.PdfPageImageFormat.png,
          backgroundColor: '#ffffff',
        );
        if (rendered == null) {
          throw StateError('PDF page could not be rendered');
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(rendered.bytes);
        late double aspectRatio;
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          aspectRatio = descriptor.width / descriptor.height;
          descriptor.dispose();
        } finally {
          buffer.dispose();
        }
        if (!mounted || !isActive()) return null;
        if ((_pageAspectRatios[number] ?? 3 / 4) != aspectRatio) {
          unawaited(_updatePdfAspectRatio(number, aspectRatio));
        }
        return (image: MemoryImage(rendered.bytes), aspectRatio: aspectRatio);
      } finally {
        await page.close();
      }
    });
    _pendingRender = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _logger.warning('Failed to render PDF page', error, stack);
      },
    );
    return result;
  }

  Future<void> _updatePdfAspectRatio(int number, double aspectRatio) async {
    while (_pdfInteraction != null) {
      await _pdfInteraction!.future;
    }
    if (!mounted || _pageAspectRatios[number] == aspectRatio) return;
    setState(() {
      _pageAspectRatios[number] = aspectRatio;
      _pdfLayoutRevision++;
    });
  }

  Future<void> _closeDocument() async {
    try {
      // Native pages must finish rendering and close before their document.
      await _pendingRender;
      await _document?.close();
    } catch (error, stack) {
      _logger.warning('Failed to close PDF document', error, stack);
    }
  }

  @override
  void dispose() {
    _pdfInteraction?.complete();
    _pdfInteraction = null;
    unawaited(_closeDocument());
    _image?.evict();
    _transformation.dispose();
    _pdfTransformation.dispose();
    _pdfPage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      extendBodyBehindAppBar: true,
      appBar: _overlayToolbar(
        AppBar(
          backgroundColor: colors.backgroundBase,
          foregroundColor: colors.textBase,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: _toolbarHeight,
          leading: IconButtonComponent(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01),
            variant: IconButtonComponentVariant.unfilled,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.maybePop(context),
          ),
          title: Tooltip(
            message: widget.fileName,
            child: Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.display3.copyWith(color: colors.textBase),
            ),
          ),
          actions: [
            if (widget.onShare != null)
              IconButtonComponent(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare08),
                variant: IconButtonComponentVariant.unfilled,
                tooltip: l10n.shareLink,
                onTap: () => widget.onShare!(context),
              ),
            Builder(
              builder: (buttonContext) => IconButtonComponent(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
                variant: IconButtonComponentVariant.unfilled,
                tooltip: l10n.more,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  final action = await showEntePopupMenu<_ViewerAction>(
                    context: buttonContext,
                    options: [
                      if (widget.onDownload != null)
                        EntePopupMenuOption(
                          value: _ViewerAction.download,
                          label: l10n.download,
                        ),
                      EntePopupMenuOption(
                        value: _ViewerAction.openExternally,
                        label: l10n.openInAnotherApp,
                      ),
                    ],
                  );
                  if (!context.mounted || action == null) return;
                  switch (action) {
                    case _ViewerAction.download:
                      await widget.onDownload!(context);
                    case _ViewerAction.openExternally:
                      await widget.onOpenExternally(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => _setToolbarVisible(!_toolbarVisible),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? _buildError(context)
                : widget.isPdf
                ? _buildPdf(context)
                : InteractiveViewer(
                    transformationController: _transformation,
                    minScale: 1,
                    maxScale: 4,
                    onInteractionUpdate: _onZoom,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        Spacing.lg,
                        _toolbarHeight + Spacing.lg,
                        Spacing.lg,
                        Spacing.lg,
                      ),
                      child: SizedBox.expand(
                        child: Image(
                          image: _image!,
                          fit: BoxFit.contain,
                          frameBuilder: (_, child, frame, synchronous) =>
                              synchronous || frame != null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(),
                                ),
                          errorBuilder: (_, error, stack) =>
                              _buildError(context),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  int _pageAt(double y) {
    var low = 0;
    var high = _pdfPageOffsets.length - 2;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_pdfPageOffsets[middle] <= y) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  void _updatePdfPage() {
    if (_pdfPageOffsets.length < 2) return;
    final center = _pdfTransformation.toScene(
      Offset(_pdfViewport.width / 2, _pdfViewport.height / 2),
    );
    _pdfPage.value = _pageAt(center.dy) + 1;
  }

  Widget _buildPdf(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Keep the same point on the visible page when lazy page sizes change.
      final anchor = _pdfTransformation.toScene(
        _pdfViewport.center(Offset.zero),
      );
      final anchorPage = _pageAt(anchor.dy);
      final anchorFraction = _pdfPageOffsets.isEmpty
          ? null
          : (anchor.dy - _pdfPageOffsets[anchorPage]) /
                (_pdfPageOffsets[anchorPage + 1] -
                    _pdfPageOffsets[anchorPage] -
                    Spacing.md);
      _pdfViewport = constraints.biggest;
      final width = constraints.maxWidth - Spacing.lg * 2;
      _pdfPageOffsets = [_toolbarHeight + Spacing.lg];
      for (var page = 1; page <= _document!.pagesCount; page++) {
        _pdfPageOffsets.add(
          _pdfPageOffsets.last +
              width / (_pageAspectRatios[page] ?? 3 / 4) +
              Spacing.md,
        );
      }
      final height = math.max(
        constraints.maxHeight,
        _pdfPageOffsets.last - Spacing.md + Spacing.lg,
      );
      final anchorShift = anchorFraction == null
          ? 0.0
          : _pdfPageOffsets[anchorPage] +
                anchorFraction *
                    (_pdfPageOffsets[anchorPage + 1] -
                        _pdfPageOffsets[anchorPage] -
                        Spacing.md) -
                anchor.dy;
      final matrix = _pdfTransformation.value.clone();
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      final x = translation.x.clamp(
        math.min(0.0, constraints.maxWidth * (1 - scale)),
        0.0,
      );
      final y = (translation.y == 0 ? 0.0 : translation.y - anchorShift * scale)
          .clamp(constraints.maxHeight - height * scale, 0.0);
      if (x != translation.x || y != translation.y) {
        matrix.setTranslationRaw(x.toDouble(), y.toDouble(), 0);
        _pdfTransformation.value = matrix;
      }
      _updatePdfPage();
      return Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer.builder(
            // Reflow invalidates the old gesture and inertia coordinates.
            key: ValueKey('pdf-layout-$_pdfLayoutRevision'),
            transformationController: _pdfTransformation,
            alignment: Alignment.topLeft,
            minScale: 1,
            maxScale: 4,
            onInteractionUpdate: _onZoom,
            onInteractionStart: (_) => _pdfInteraction ??= Completer<void>(),
            onInteractionEnd: (_) {
              _pdfInteraction?.complete();
              _pdfInteraction = null;
            },
            builder: (context, viewport) {
              final first = math.max(0, _pageAt(viewport.point0.y) - 1);
              final last = math.min(
                _document!.pagesCount - 1,
                _pageAt(viewport.point2.y) + 1,
              );
              return SizedBox(
                // Keep rendered tiles alive when the gesture state is reset.
                key: _pdfContentKey,
                width: constraints.maxWidth,
                height: height,
                child: Stack(
                  children: [
                    for (var index = first; index <= last; index++)
                      Positioned(
                        key: ValueKey(index),
                        top: _pdfPageOffsets[index],
                        left: Spacing.lg,
                        right: Spacing.lg,
                        height:
                            _pdfPageOffsets[index + 1] -
                            _pdfPageOffsets[index] -
                            Spacing.md,
                        child: _PdfPageTile(
                          number: index + 1,
                          renderPage: _renderPage,
                          errorBuilder: _buildError,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: IgnorePointer(
                child: ValueListenableBuilder<int>(
                  valueListenable: _pdfPage,
                  builder: (context, page, _) => Semantics(
                    label: context.strings.scanPageOfTotal(
                      current: page,
                      total: _document!.pagesCount,
                    ),
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth / 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: context.componentColors.fillDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$page / ${_document!.pagesCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.mini.copyWith(
                            color: context.componentColors.textBase,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildError(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.errorOpeningFile,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          ButtonComponent(
            label: context.strings.openInAnotherApp,
            onTap: () => widget.onOpenExternally(context),
          ),
        ],
      ),
    ),
  );
}

class _PdfPageTile extends StatefulWidget {
  const _PdfPageTile({
    required this.number,
    required this.renderPage,
    required this.errorBuilder,
  });

  final int number;
  final Future<_RenderedPdfPage?> Function(int, bool Function()) renderPage;
  final WidgetBuilder errorBuilder;

  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  _RenderedPdfPage? _rendered;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rendered = await widget.renderPage(widget.number, () => mounted);
      if (mounted) {
        setState(() => _rendered = rendered);
      } else {
        unawaited(rendered?.image.evict());
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _rendered?.image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _failed
      ? widget.errorBuilder(context)
      : _rendered == null
      ? const Center(child: CircularProgressIndicator())
      : Image(
          image: _rendered!.image,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => widget.errorBuilder(context),
        );
}
