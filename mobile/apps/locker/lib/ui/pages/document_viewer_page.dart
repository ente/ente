import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
  final _pageAspectRatios = <int, double>{};
  pdf.PdfDocument? _document;
  Future<void>? _pendingRender;
  ImageProvider? _image;
  bool _loading = false;
  bool _failed = false;
  final _zoomedPdfPages = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) {
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
        _pageAspectRatios[number] = page.width / page.height;
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
        if (!mounted || !isActive()) return null;
        return (
          image: MemoryImage(rendered.bytes),
          aspectRatio: page.width / page.height,
        );
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
    unawaited(_closeDocument());
    _image?.evict();
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        backgroundColor: colors.backgroundBase,
        foregroundColor: colors.textBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: math.max(
          kToolbarHeight,
          MediaQuery.textScalerOf(context).scale(20) * 1.4,
        ),
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
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? _buildError(context)
            : widget.isPdf
            ? Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.all(Spacing.lg),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  addAutomaticKeepAlives: false,
                  physics: _zoomedPdfPages.isNotEmpty
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: _document!.pagesCount,
                  itemBuilder: (context, index) => _PdfPageTile(
                    key: ValueKey(index),
                    number: index + 1,
                    total: _document!.pagesCount,
                    aspectRatio: _pageAspectRatios[index + 1] ?? 3 / 4,
                    renderPage: _renderPage,
                    errorBuilder: _buildError,
                    onZoomChanged: (zoomed) {
                      if (mounted && _zoomedPdfPages.contains(index) != zoomed) {
                        setState(() {
                          if (zoomed) {
                            _zoomedPdfPages.add(index);
                          } else {
                            _zoomedPdfPages.remove(index);
                          }
                        });
                      }
                    },
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: InteractiveViewer(
                  transformationController: _transformation,
                  minScale: 1,
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: Image(
                      image: _image!,
                      fit: BoxFit.contain,
                      frameBuilder: (_, child, frame, synchronous) =>
                          synchronous || frame != null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, error, stack) => _buildError(context),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

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
    super.key,
    required this.number,
    required this.total,
    required this.aspectRatio,
    required this.renderPage,
    required this.errorBuilder,
    required this.onZoomChanged,
  });

  final int number;
  final int total;
  final double aspectRatio;
  final Future<_RenderedPdfPage?> Function(int, bool Function()) renderPage;
  final WidgetBuilder errorBuilder;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  final _transformation = TransformationController();
  _RenderedPdfPage? _rendered;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(() {
      widget.onZoomChanged(_transformation.value.getMaxScaleOnAxis() > 1.01);
    });
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
    if (_transformation.value.getMaxScaleOnAxis() > 1.01) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onZoomChanged(false);
      });
    }
    _rendered?.image.evict();
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: _rendered?.aspectRatio ?? widget.aspectRatio,
        child: _failed
            ? widget.errorBuilder(context)
            : _rendered == null
            ? const Center(child: CircularProgressIndicator())
            : InteractiveViewer(
                transformationController: _transformation,
                minScale: 1,
                maxScale: 4,
                child: Image(
                  image: _rendered!.image,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) =>
                      widget.errorBuilder(context),
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Text(
          context.strings.scanPageOfTotal(
            current: widget.number,
            total: widget.total,
          ),
          style: TextStyles.mini.copyWith(
            color: context.componentColors.textLight,
          ),
        ),
      ),
    ],
  );
}
