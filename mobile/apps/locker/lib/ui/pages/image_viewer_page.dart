import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";

typedef ImageViewerAction = Future<void> Function(BuildContext);

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.localFile,
    required this.fileName,
    required this.onOpenExternally,
    this.onDownload,
    this.onShare,
  });

  final File localFile;
  final String fileName;
  final ImageViewerAction onOpenExternally;
  final ImageViewerAction? onDownload;
  final ImageViewerAction? onShare;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  static final _logger = Logger("ImageViewerPage");
  static const _maxScale = 3.0;
  static const _doubleTapScale = 2.5;
  static const _maxDimension = 3072;

  final _transformation = TransformationController();
  late final ImageProvider _image = ResizeImage(
    FileImage(widget.localFile),
    width: _maxDimension,
    height: _maxDimension,
    policy: ResizeImagePolicy.fit,
  );
  bool _failed = false;
  bool _toolbarVisible = true;
  Offset _doubleTapAt = Offset.zero;
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _transformation.dispose();
    unawaited(_image.evict());
    super.dispose();
  }

  void _markFailed(Object error, StackTrace? stack) {
    if (_failed) return;
    _failed = true;
    _logger.warning("Failed to decode image", error, stack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleZoom() {
    final zoomedIn = _transformation.value.getMaxScaleOnAxis() > 1.01;
    final scale = zoomedIn ? 1.0 : _doubleTapScale;
    final scene = _transformation.toScene(_doubleTapAt);
    final x = (_doubleTapAt.dx - scene.dx * scale).clamp(
      _viewport.width * (1 - scale),
      0.0,
    );
    final y = (_doubleTapAt.dy - scene.dy * scale).clamp(
      _viewport.height * (1 - scale),
      0.0,
    );
    _transformation.value = Matrix4.translationValues(x, y, 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final canHideToolbar =
        !_failed && !MediaQuery.accessibleNavigationOf(context);
    return Theme(
      data: ComponentTheme.darkTheme(app: ComponentApp.locker),
      child: Scaffold(
        backgroundColor: Colors.black,
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
          onDoubleTap: _failed ? null : _toggleZoom,
          child: _failed
              ? _ErrorMessage(onOpenExternally: widget.onOpenExternally)
              : _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_viewport != Size.zero && _viewport != constraints.biggest) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _transformation.value = Matrix4.identity();
          });
        }
        _viewport = constraints.biggest;
        return InteractiveViewer(
          transformationController: _transformation,
          minScale: 1,
          maxScale: _maxScale,
          child: Image(
            image: _image,
            width: _viewport.width,
            height: _viewport.height,
            fit: BoxFit.contain,
            semanticLabel: widget.fileName,
            frameBuilder: (context, child, frame, loadedSynchronously) {
              if (loadedSynchronously) return child;
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (frame == null) const LoadingComponent(),
                  AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                ],
              );
            },
            errorBuilder: (context, error, stack) {
              _markFailed(error, stack);
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.onOpenExternally});

  final ImageViewerAction onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
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
              l10n.errorOpeningFile,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(
                color: context.componentColors.textBase,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            ButtonComponent(
              label: l10n.openInAnotherApp,
              onTap: () => onOpenExternally(context),
            ),
          ],
        ),
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
  final ImageViewerAction onOpenExternally;
  final ImageViewerAction? onShare;
  final ImageViewerAction? onDownload;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.6),
                Colors.black.withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.025),
                Colors.transparent,
              ],
              stops: const [0, 0.2, 0.9, 0.95, 1],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: AppBar(
              backgroundColor: Colors.transparent,
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
                if (onShare != null) const SizedBox(width: Spacing.md),
                Builder(
                  builder: (buttonContext) => IconButtonComponent(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedMoreVertical,
                    ),
                    variant: IconButtonComponentVariant.unfilled,
                    tooltip: l10n.more,
                    shouldSurfaceExecutionStates: false,
                    onTap: () => _showMenu(buttonContext),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final l10n = context.strings;
    final action = await showEntePopupMenu<ImageViewerAction>(
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
