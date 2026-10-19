import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_pdf_renderer/ente_pdf_renderer.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/ui/viewer/pdf_page_layout.dart";
import "package:logging/logging.dart";

typedef PdfViewerAction = Future<void> Function(BuildContext);

enum _Status { loading, ready, locked, unsupported, failed }

class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({
    super.key,
    required this.localFile,
    required this.fileName,
    required this.onOpenExternally,
    this.onDownload,
    this.onShare,
  });

  final File localFile;
  final String fileName;
  final PdfViewerAction onOpenExternally;
  final PdfViewerAction? onDownload;
  final PdfViewerAction? onShare;

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  static final _logger = Logger("PdfViewerPage");
  static const _maxScale = 5.0;
  static const _doubleTapScale = 2.5;
  static const _maxRenderPixels = 8 * 1024 * 1024;

  final _transformation = TransformationController();
  final _currentPage = ValueNotifier(1);
  final _password = TextEditingController();
  final _tiles = <int, (MemoryImage, int)>{};
  final _queue = <int>{};
  final _failed = <int>{};

  EntePdfDocument? _document;
  PdfPageLayout? _layout;
  _Status _status = _Status.loading;
  bool _wrongPassword = false;
  int _renderScale = 1;
  double _pixelRatio = 1;
  bool _rendering = false;
  bool _toolbarVisible = true;
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_updateCurrentPage);
    unawaited(_open(null));
  }

  @override
  void dispose() {
    _transformation.dispose();
    _currentPage.dispose();
    _password.dispose();
    _evictTiles();
    unawaited(_document?.close());
    super.dispose();
  }

  Future<void> _open(String? password) async {
    setState(() {
      _status = _Status.loading;
      _wrongPassword = false;
    });
    try {
      final document = await EntePdfRenderer.open(
        widget.localFile.path,
        password: password,
      );
      if (!mounted || document.pageCount == 0) {
        await document.close();
        if (mounted) setState(() => _status = _Status.failed);
        return;
      }
      setState(() {
        _document = document;
        _status = _Status.ready;
      });
    } on PdfPasswordRequiredException {
      if (mounted) setState(() => _status = _Status.locked);
    } on PdfPasswordIncorrectException {
      _wrongPassword = true;
      if (mounted) setState(() => _status = _Status.locked);
    } on PdfPasswordUnsupportedException {
      if (mounted) setState(() => _status = _Status.unsupported);
    } catch (e, s) {
      _logger.warning("Failed to open PDF", e, s);
      if (mounted) setState(() => _status = _Status.failed);
    }
  }

  void _evictTiles() {
    for (final (image, _) in _tiles.values) {
      unawaited(image.evict());
    }
    _tiles.clear();
    _queue.clear();
    _failed.clear();
  }

  PdfPageLayout _layoutFor(Size viewport) {
    final current = _layout;
    if (current?.viewportWidth != viewport.width) {
      _evictTiles();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _transformation.value = Matrix4.identity();
      });
    } else if (current!.viewportHeight == viewport.height) {
      return current;
    }
    final padding = MediaQuery.paddingOf(context);
    return _layout = PdfPageLayout(
      pageSizes: _document!.pageSizes,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
      topInset: padding.top + kToolbarHeight + Spacing.lg,
      bottomPadding: Spacing.lg + padding.bottom,
    );
  }

  int _wantedWidth(int index) => _layout!.renderWidth(
    index,
    pixelRatio: _pixelRatio,
    scale: _renderScale,
    maxPixels: _maxRenderPixels,
  );

  void _requestTiles(int first, int last) {
    _tiles.removeWhere((index, tile) {
      final far = index < first - 2 || index > last + 2;
      if (far) unawaited(tile.$1.evict());
      return far;
    });
    _queue.removeWhere((index) => index < first || index > last);
    for (var index = first; index <= last; index++) {
      if (_tiles[index]?.$2 != _wantedWidth(index) &&
          !_failed.contains(index)) {
        _queue.add(index);
      }
    }
    if (!_rendering) unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    _rendering = true;
    while (_queue.isNotEmpty && mounted) {
      final index = _queue.first;
      _queue.remove(index);
      final width = _wantedWidth(index);
      if (_tiles[index]?.$2 == width) continue;
      try {
        final bytes = await _document!.render(
          index + 1,
          width: width,
          height: _layout!.renderHeight(index, width),
        );
        if (!mounted) return;
        unawaited(_tiles[index]?.$1.evict());
        setState(() => _tiles[index] = (MemoryImage(bytes), width));
      } catch (e, s) {
        _logger.warning("Failed to render PDF page ${index + 1}", e, s);
        if (mounted) setState(() => _failed.add(index));
      }
    }
    _rendering = false;
  }

  void _updateCurrentPage() {
    final layout = _layout;
    if (layout == null) return;
    final top = _transformation.toScene(Offset.zero).dy;
    final bottom = _transformation.toScene(Offset(0, layout.viewportHeight)).dy;
    _currentPage.value = layout.currentPage(top, bottom) + 1;
  }

  void _updateRenderScale() {
    final scale = PdfPageLayout.zoomBucket(
      _transformation.value.getMaxScaleOnAxis(),
      maxScale: _maxScale,
    );
    if (scale != _renderScale) setState(() => _renderScale = scale);
  }

  void _toggleZoom() {
    final layout = _layout!;
    final zoomedIn = _transformation.value.getMaxScaleOnAxis() > 1.01;
    final scale = zoomedIn ? 1.0 : _doubleTapScale;
    final scene = _transformation.toScene(_doubleTapAt);
    final x = (_doubleTapAt.dx - scene.dx * scale).clamp(
      layout.viewportWidth * (1 - scale),
      0.0,
    );
    final y = layout.clampTranslationY(
      _doubleTapAt.dy - scene.dy * scale,
      scale,
    );
    _transformation.value = Matrix4.translationValues(x, y, 0)
      ..scaleByDouble(scale, scale, 1, 1);
    _updateRenderScale();
  }

  void _scrollBy(double direction) {
    final layout = _layout!;
    final matrix = _transformation.value.clone();
    final translation = matrix.getTranslation();
    final scale = matrix.getMaxScaleOnAxis();
    final step = (layout.viewportHeight - kToolbarHeight) * 0.8;
    final y = layout.clampTranslationY(translation.y - direction * step, scale);
    matrix.setTranslationRaw(translation.x, y, 0);
    _transformation.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _status == _Status.ready;
    final canHideToolbar = ready && !MediaQuery.accessibleNavigationOf(context);
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      extendBodyBehindAppBar: true,
      appBar: _Toolbar(
        visible: _toolbarVisible || !canHideToolbar,
        fileName: widget.fileName,
        onShare: widget.onShare,
        onDownload: widget.onDownload,
        onOpenExternally: widget.onOpenExternally,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: canHideToolbar
            ? () => setState(() => _toolbarVisible = !_toolbarVisible)
            : null,
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: ready ? _toggleZoom : null,
        child: Stack(
          children: [
            Positioned.fill(child: _body()),
            if (ready)
              _PageIndicator(page: _currentPage, total: _document!.pageCount),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final l10n = context.strings;
    final openExternally = ButtonComponent(
      label: l10n.openInAnotherApp,
      onTap: () => widget.onOpenExternally(context),
    );
    switch (_status) {
      case _Status.loading:
        return const Center(child: LoadingComponent());
      case _Status.failed:
        return _Message(text: l10n.errorOpeningFile, action: openExternally);
      case _Status.unsupported:
        return _Message(
          text: l10n.pdfPasswordNotSupportedOnDevice,
          action: openExternally,
        );
      case _Status.locked:
        return _Message(
          text: l10n.pdfNeedsPassword,
          field: TextInputComponent(
            controller: _password,
            label: l10n.password,
            isPasswordInput: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            message: _wrongPassword ? l10n.incorrectPasswordTitle : null,
            messageType: TextInputComponentMessageType.error,
            onSubmit: _open,
          ),
          action: ButtonComponent(
            label: l10n.unlockPdf,
            shouldSurfaceExecutionStates: false,
            onTap: () => _open(_password.text),
          ),
        );
      case _Status.ready:
        return LayoutBuilder(
          builder: (context, constraints) => _pages(constraints),
        );
    }
  }

  Widget _pages(BoxConstraints constraints) {
    final layout = _layoutFor(constraints.biggest);
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      container: true,
      onScrollUp: () => _scrollBy(-1),
      onScrollDown: () => _scrollBy(1),
      child: InteractiveViewer.builder(
        transformationController: _transformation,
        minScale: 1,
        maxScale: _maxScale,
        onInteractionEnd: (_) => _updateRenderScale(),
        builder: (context, viewport) {
          final (first, last) = layout.visibleRange(
            viewport.point0.y,
            viewport.point2.y,
            margin: _renderScale == 1 ? 1 : 0,
          );
          _requestTiles(first, last);
          return SizedBox(
            width: layout.viewportWidth,
            height: layout.contentHeight,
            child: Stack(
              children: [
                for (var index = first; index <= last; index++)
                  Positioned(
                    key: ValueKey(index),
                    top: layout.pageTop(index),
                    left: PdfPageLayout.horizontalPadding,
                    width: layout.contentWidth,
                    height: layout.pageHeight(index),
                    child: RepaintBoundary(
                      child: _PageTile(
                        image: _tiles[index]?.$1,
                        failed: _failed.contains(index),
                        onOpenExternally: widget.onOpenExternally,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget implements PreferredSizeWidget {
  const _Toolbar({
    required this.visible,
    required this.fileName,
    required this.onOpenExternally,
    this.onShare,
    this.onDownload,
  });

  final bool visible;
  final String fileName;
  final PdfViewerAction onOpenExternally;
  final PdfViewerAction? onShare;
  final PdfViewerAction? onDownload;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: AppBar(
        backgroundColor: colors.backgroundBase,
        foregroundColor: colors.textBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        actionsPadding: const EdgeInsetsDirectional.only(end: Spacing.sm),
        leading: IconButtonComponent(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01),
          variant: IconButtonComponentVariant.unfilled,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onTap: () => Navigator.maybePop(context),
        ),
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyles.display3.copyWith(color: colors.textBase),
        ),
        actions: [
          if (onShare != null)
            IconButtonComponent(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare08),
              variant: IconButtonComponentVariant.unfilled,
              tooltip: l10n.shareLink,
              shouldSurfaceExecutionStates: false,
              onTap: () => onShare!(context),
            ),
          Builder(
            builder: (buttonContext) => IconButtonComponent(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
              variant: IconButtonComponentVariant.unfilled,
              tooltip: l10n.more,
              shouldSurfaceExecutionStates: false,
              onTap: () => _showMenu(buttonContext),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final l10n = context.strings;
    final action = await showEntePopupMenu<PdfViewerAction>(
      context: context,
      options: [
        if (onDownload != null)
          EntePopupMenuOption(value: onDownload!, label: l10n.download),
        EntePopupMenuOption(
          value: onOpenExternally,
          label: l10n.openInAnotherApp,
        ),
      ],
    );
    if (action != null && context.mounted) await action(context);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action, this.field});

  final String text;
  final Widget action;
  final Widget? field;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.xxl,
          MediaQuery.paddingOf(context).top + kToolbarHeight + Spacing.xxl,
          Spacing.xxl,
          Spacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(
                color: context.componentColors.textBase,
              ),
            ),
            if (field != null) ...[const SizedBox(height: Spacing.xl), field!],
            const SizedBox(height: Spacing.xl),
            action,
          ],
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.image,
    required this.failed,
    required this.onOpenExternally,
  });

  final MemoryImage? image;
  final bool failed;
  final PdfViewerAction onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: colors.specialScrim.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.strings.errorOpeningFile,
                    textAlign: TextAlign.center,
                    style: TextStyles.body.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: Spacing.lg),
                  ButtonComponent(
                    label: context.strings.openInAnotherApp,
                    onTap: () => onOpenExternally(context),
                  ),
                ],
              ),
            )
          : image == null
          ? null
          : Image(image: image!, fit: BoxFit.fill, gaplessPlayback: true),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.page, required this.total});

  final ValueListenable<int> page;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Positioned(
      right: Spacing.md,
      bottom: Spacing.xl + MediaQuery.paddingOf(context).bottom,
      child: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (context, page, _) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.fillDark,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Text(
            "$page / $total",
            semanticsLabel: context.strings.scanPageOfTotal(
              current: page,
              total: total,
            ),
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ),
      ),
    );
  }
}
