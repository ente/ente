import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:pdfx/pdfx.dart' as pdf;

enum _ViewerAction { download, openExternally }

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
  final _scrollController = ScrollController();
  final _transformation = TransformationController();
  pdf.PdfDocument? _document;
  Future<void>? _pendingRender;
  ImageProvider? _image;
  int _page = 1;
  bool _loading = false;
  bool _failed = false;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_onZoomChanged);
    if (widget.isPdf) {
      _loading = true;
      _pendingRender = _renderPage(1);
    } else {
      _image = ResizeImage(
        FileImage(widget.localFile),
        width: _maxImageDimension,
        height: _maxImageDimension,
        policy: ResizeImagePolicy.fit,
      );
    }
  }

  void _showPage(int page) {
    if (_loading) return;
    _image?.evict();
    setState(() {
      _loading = true;
      _failed = false;
      _image = null;
      _page = page;
    });
    _transformation.value = Matrix4.identity();
    _pendingRender = _renderPage(page);
  }

  Future<void> _renderPage(int number) async {
    try {
      _document ??= await widget.openPdf(widget.localFile.path);
      if (!mounted) return;
      final page = await _document!.getPage(number);
      pdf.PdfPageImage? rendered;
      try {
        if (!mounted) return;
        final scale = _maxImageDimension / math.max(page.width, page.height);
        rendered = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdf.PdfPageImageFormat.png,
          backgroundColor: '#ffffff',
        );
        if (rendered == null) {
          throw StateError('PDF page could not be rendered');
        }
      } finally {
        await page.close();
      }
      if (!mounted) return;
      setState(() {
        _page = number;
        _image = MemoryImage(rendered!.bytes);
        _loading = false;
      });
    } catch (error, stack) {
      _logger.warning('Failed to render PDF page', error, stack);
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
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
    _scrollController.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != 1 ||
        _transformation.value.getMaxScaleOnAxis() > 1.01 ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels - details.focalPointDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _onZoomChanged() {
    final zoomed = _transformation.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: widget.fileName,
        controller: _scrollController,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
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
        slivers: [
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: SizedBox(
                height: constraints.remainingPaintExtent,
                child: SafeArea(
                  top: false,
                  bottom: !widget.isPdf,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _failed
                        ? _buildError(context)
                        : InteractiveViewer(
                            transformationController: _transformation,
                            minScale: 1,
                            maxScale: 4,
                            onInteractionUpdate: _onInteractionUpdate,
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
          ),
        ],
      ),
      bottomNavigationBar: widget.isPdf && (_document?.pagesCount ?? 0) > 0
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Row(
                  children: [
                    IconButtonComponent(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                      ),
                      variant: IconButtonComponentVariant.unfilled,
                      tooltip: l10n.previous,
                      onTap: !_loading && _page > 1
                          ? () => _showPage(_page - 1)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        l10n.scanPageOfTotal(
                          current: _page,
                          total: _document!.pagesCount,
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ),
                    IconButtonComponent(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight01,
                      ),
                      variant: IconButtonComponentVariant.unfilled,
                      tooltip: l10n.next,
                      onTap: !_loading && _page < _document!.pagesCount
                          ? () => _showPage(_page + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            )
          : null,
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
