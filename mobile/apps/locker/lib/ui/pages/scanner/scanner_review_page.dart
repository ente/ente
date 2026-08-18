import 'dart:async';
import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:locker/services/scanner/scan_session_controller.dart';
import 'package:locker/services/scanner/scanner_models.dart';
import 'package:locker/ui/components/text_input_sheet.dart';
import 'package:locker/ui/pages/scanner/scanner_crop_page.dart';
import 'package:share_plus/share_plus.dart';

class ScannerReviewPage extends StatefulWidget {
  const ScannerReviewPage({
    super.key,
    required this.session,
    required this.onUploadFiles,
  });

  final ScanSessionController session;
  final Future<bool> Function(List<File> files) onUploadFiles;

  @override
  State<ScannerReviewPage> createState() => _ScannerReviewPageState();
}

class _ScannerReviewPageState extends State<ScannerReviewPage> {
  static const _thumbnailWidth = 40.0;
  static const _thumbnailHeight = 56.0;

  late final PageController _pageController;
  int _index = 0;
  bool _operationInFlight = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _index = widget.session.pageCount - 1;
    if (_index < 0) _index = 0;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefix = context.strings.scanFilenamePrefix;
    final timestamp = DateFormat('d MMM yyyy, HH.mm').format(DateTime.now());
    widget.session.ensureFileName('$prefix $timestamp.pdf');
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (widget.session.pageCount == 0 && !widget.session.isProcessing) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      if (_index >= widget.session.pageCount && widget.session.pageCount > 0) {
        _index = widget.session.pageCount - 1;
      }
    });
  }

  ScannedPage? get _currentPage {
    final pages = widget.session.pages;
    if (pages.isEmpty) return null;
    return pages[_index.clamp(0, pages.length - 1)];
  }

  Future<File> _buildPdf() async {
    await widget.session.waitForPending();
    return widget.session.buildPdf();
  }

  Future<void> _runExclusive(Future<void> Function() operation) async {
    if (_operationInFlight) return;
    setState(() => _operationInFlight = true);
    try {
      await operation();
    } finally {
      if (mounted) setState(() => _operationInFlight = false);
    }
  }

  Future<void> _saveToEnte() => _runExclusive(() async {
    final pdf = await _buildPdf();
    if (!mounted) return;
    final didUpload = await widget.onUploadFiles([pdf]);
    if (!mounted) return;
    if (didUpload) {
      showShortToast(context, context.strings.scanSaved);
      Navigator.of(context).pop(true);
    }
  });

  Future<void> _share() => _runExclusive(() async {
    final pdf = await _buildPdf();
    await SharePlus.instance.share(ShareParams(files: [XFile(pdf.path)]));
  });

  Future<void> _rename() async {
    final l10n = context.strings;
    final current = widget.session.fileName ?? '';
    final base = current.toLowerCase().endsWith('.pdf')
        ? current.substring(0, current.length - 4)
        : current;
    await showTextInputSheet(
      context,
      title: l10n.renameFile,
      initialValue: base,
      hintText: l10n.enterFileName,
      submitButtonLabel: l10n.save,
      onSubmit: (String name) async => widget.session.renameFile(name),
    );
  }

  Future<void> _adjustCrop() => _runExclusive(() async {
    final page = _currentPage;
    if (page == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ScannerCropPage(session: widget.session, pageId: page.id),
      ),
    );
  });

  Future<void> _rotate() => _runExclusive(() async {
    final page = _currentPage;
    if (page == null) return;
    await widget.session.rotatePageClockwise(page.id);
  });

  Future<void> _delete() => _runExclusive(() async {
    final page = _currentPage;
    if (page == null) return;
    await widget.session.deletePage(page.id);
  });

  void _jumpToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: Motion.standard,
      curve: Curves.easeInOut,
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final pages = widget.session.pages;
    if (pages.isEmpty) return;
    final viewedId = pages[_index.clamp(0, pages.length - 1)].id;
    widget.session.reorderPage(oldIndex, newIndex);
    final target = widget.session.pages.indexWhere(
      (page) => page.id == viewedId,
    );
    if (target >= 0 && target != _index) {
      setState(() => _index = target);
      _pageController.jumpToPage(target);
    }
  }

  static String _elideMiddle(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final half = (maxLength - 1) ~/ 2;
    return '${text.substring(0, half)}…${text.substring(text.length - half)}';
  }

  Widget _buildFileNameField(ColorTokens colors) {
    final fileName = widget.session.fileName ?? '';
    return Tooltip(
      message: context.strings.renameFile,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _rename,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: colors.strokeFaint),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _elideMiddle(fileName, 26),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.bodyBold.copyWith(color: colors.textBase),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              HugeIcon(
                icon: HugeIcons.strokeRoundedPencilEdit02,
                color: colors.primary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip(
    List<ScannedPage> pages,
    int current,
    ColorTokens colors,
  ) {
    return SizedBox(
      height: _thumbnailHeight + 2 * Spacing.xs,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.xs,
        ),
        itemCount: pages.length,
        onReorder: _onReorder,
        itemBuilder: (context, index) {
          final page = pages[index];
          final isCurrent = index == current;
          return Padding(
            key: ValueKey(page.id),
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: GestureDetector(
              onTap: () => _jumpToPage(index),
              child: Container(
                width: _thumbnailWidth,
                height: _thumbnailHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: isCurrent ? colors.primary : colors.strokeDark,
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.xs - 1),
                  child: Image.file(
                    page.processedJpeg,
                    key: ValueKey(page.processedJpeg.path),
                    fit: BoxFit.cover,
                    cacheHeight: 168,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _operationInFlight,
          child: ListenableBuilder(
            listenable: widget.session,
            builder: (context, _) {
              final pages = widget.session.pages;
              final pageCount = pages.length;
              final current = pageCount == 0
                  ? 0
                  : _index.clamp(0, pageCount - 1);
              return Column(
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
                            icon: HugeIcons.strokeRoundedArrowLeft01,
                            color: colors.textBase,
                          ),
                          variant: IconButtonComponentVariant.unfilled,
                          onTap: () => Navigator.of(context).pop(false),
                          tooltip: l10n.addPage,
                        ),
                        Expanded(
                          child: Center(child: _buildFileNameField(colors)),
                        ),
                        IconButtonComponent(
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedCameraAdd01,
                            color: colors.textBase,
                          ),
                          variant: IconButtonComponentVariant.unfilled,
                          onTap: () => Navigator.of(context).pop(false),
                          tooltip: l10n.addPage,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: pageCount == 0
                        ? const Center(child: CircularProgressIndicator())
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: pageCount,
                            onPageChanged: (index) =>
                                setState(() => _index = index),
                            itemBuilder: (context, index) {
                              final page = pages[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.lg,
                                  vertical: Spacing.sm,
                                ),
                                child: Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      Radii.sm,
                                    ),
                                    child: Image.file(
                                      page.processedJpeg,
                                      key: ValueKey(page.processedJpeg.path),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (pageCount > 0)
                    Text(
                      l10n.scanPageOfTotal(
                        current: current + 1,
                        total: pageCount,
                      ),
                      style: TextStyles.mini.copyWith(
                        color: colors.textLighter,
                      ),
                    ),
                  const SizedBox(height: Spacing.sm),
                  if (pageCount > 1) ...[
                    _buildThumbnailStrip(pages, current, colors),
                    const SizedBox(height: Spacing.sm),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButtonComponent(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCrop,
                          color: colors.textBase,
                        ),
                        onTap: pageCount == 0 ? null : _adjustCrop,
                        tooltip: l10n.adjustCrop,
                      ),
                      const SizedBox(width: Spacing.lg),
                      IconButtonComponent(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedRotateClockwise,
                          color: colors.textBase,
                        ),
                        onTap: pageCount == 0 ? null : _rotate,
                        tooltip: l10n.rotate,
                      ),
                      const SizedBox(width: Spacing.lg),
                      IconButtonComponent(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete02,
                          color: colors.warning,
                        ),
                        onTap: pageCount == 0 ? null : _delete,
                        tooltip: l10n.delete,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Column(
                      children: [
                        ButtonComponent(
                          label: l10n.saveToEnte,
                          onTap: pageCount == 0 && !widget.session.isProcessing
                              ? null
                              : _saveToEnte,
                        ),
                        const SizedBox(height: Spacing.md),
                        ButtonComponent(
                          label: l10n.share,
                          variant: ButtonComponentVariant.secondary,
                          onTap: pageCount == 0 && !widget.session.isProcessing
                              ? null
                              : _share,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
