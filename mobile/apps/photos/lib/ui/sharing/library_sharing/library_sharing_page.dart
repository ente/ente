import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/library_sharing/library_sharing_recipient.dart';
import 'package:photos/services/library_sharing_service.dart';
import 'package:photos/ui/collections/flex_grid_view.dart';
import 'package:photos/ui/components/empty_state_component.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_role_badge.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_selection_sheet.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_sheets.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_strings.dart';

class LibrarySharingPage extends StatefulWidget {
  const LibrarySharingPage({
    required this.recipient,
    this.controller,
    super.key,
  });

  final LibrarySharingRecipient recipient;
  final LibrarySharingController? controller;

  @override
  State<LibrarySharingPage> createState() => _LibrarySharingPageState();
}

class _LibrarySharingPageState extends State<LibrarySharingPage> {
  late final LibrarySharingController _controller =
      widget.controller ??
      LibrarySharingController(
        recipient: widget.recipient,
        repository: LibrarySharingService(),
      );
  late final bool _ownsController = widget.controller == null;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectionSheetKey = GlobalKey();
  bool _isSelectionSheetExpanded = true;
  bool _selectionSheetWasVisible = false;
  double? _expandedSelectionSheetHeight;

  LibrarySharingRecipient get _recipient => _controller.recipient;

  @override
  void initState() {
    super.initState();
    _selectionSheetWasVisible = _showSelectionSheet;
    _controller.addListener(_handleControllerChange);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _scrollController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop:
            !_controller.isMutating &&
            (!_controller.isSelecting || _controller.isFirstTime),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _controller.isSelecting && !_controller.isMutating) {
            _controller.exitSelectionMode();
          }
        },
        child: Scaffold(
          backgroundColor: context.componentColors.backgroundBase,
          body: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final showSelectionSheet = _showSelectionSheet;
    if (showSelectionSheet && _isSelectionSheetExpanded) {
      _scheduleSelectionSheetMeasurement();
    }
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<UserScrollNotification>(
            onNotification: _handleUserScroll,
            child: _content(context),
          ),
        ),
        if (showSelectionSheet)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSize(
              duration: Motion.standard,
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: LibrarySharingSelectionSheet(
                key: _selectionSheetKey,
                controller: _controller,
                isExpanded: _isSelectionSheetExpanded,
                onExpandedChanged: _setSelectionSheetExpanded,
                onApply: _applySelection,
                onStopSharing: _stopSharing,
                onShowMixedRoles: () => unawaited(_showMixedRoles()),
              ),
            ),
          ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    return AppBarComponent(
      title: _recipient.label,
      titleBuilderHeight: _titleBuilderHeight(context),
      titleBuilder: _titleBuilder,
      controller: _scrollController,
      onBack: () => Navigator.of(context).maybePop(),
      actions: [
        if (!_controller.isFirstTime && !_controller.isSelecting)
          IconButtonComponent(
            tooltip: LibrarySharingStrings.shareAlbums,
            variant: IconButtonComponentVariant.primary,
            shouldSurfaceExecutionStates: false,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedImageAdd01,
              size: IconSizes.small,
            ),
            onTap: _controller.enterAddMode,
          ),
      ],
      slivers: _slivers(context),
    );
  }

  bool get _showSelectionSheet =>
      _controller.isSelecting && _controller.hasSelection;

  Widget _titleBuilder(BuildContext context, HeaderAppBarTitleState state) {
    final colors = context.componentColors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _controller.isAddingAlbums
              ? LibrarySharingStrings.shareWith
              : LibrarySharingStrings.sharingWith,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _librarySharingEyebrowStyle.copyWith(color: colors.textLight),
        ),
        Text(
          _recipient.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: state.textStyle.copyWith(color: colors.textBase),
        ),
      ],
    );
  }

  List<Widget> _slivers(BuildContext context) {
    if (_controller.isLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_controller.loadError != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  LibrarySharingStrings.loadFailed,
                  style: TextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.lg),
                ButtonComponent(
                  label: LibrarySharingStrings.retryLoading,
                  onTap: _controller.load,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final albums = _controller.visibleAlbums;
    final leadingSlivers = <Widget>[
      if (!_controller.isAddingAlbums || _controller.isFirstTime)
        _librarySharingBanner(),
    ];
    if (albums.isEmpty) {
      final isSharingFullLibrary =
          _controller.isAddingAlbums && _controller.eligibleAlbumCount > 0;
      return [
        ...leadingSlivers,
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateComponent(
            assetPath: isSharingFullLibrary
                ? 'assets/ducky_full_library.png'
                : 'assets/ducky_share.png',
            title: isSharingFullLibrary
                ? LibrarySharingStrings.allCurrentAlbumsShared
                : LibrarySharingStrings.noAlbumsToShare,
            textWidth: isSharingFullLibrary ? 257 : 285,
            alignment: isSharingFullLibrary
                ? Alignment.topCenter
                : Alignment.center,
            padding: isSharingFullLibrary
                ? const EdgeInsets.only(top: _fullLibraryEmptyStateTopPadding)
                : const EdgeInsets.fromLTRB(
                    Spacing.xl,
                    0,
                    Spacing.xl,
                    Spacing.xl,
                  ),
          ),
        ),
      ];
    }
    return [
      ...leadingSlivers,
      CollectionsFlexiGridViewWidget(
        albums,
        tag: 'library_sharing_${_recipient.userID}',
        onlyAllowSelection: true,
        onCollectionTap: _handleAlbumTap,
        isCollectionSelected: _controller.isSelected,
        topLeftOverlayBuilder: _roleOverlay,
        topPadding: Spacing.sm,
        bottomPadding: _gridBottomPadding,
        gridLayout: AlbumGridLayout.dense,
      ),
    ];
  }

  Widget _librarySharingBanner() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        Spacing.md,
      ),
      sliver: SliverToBoxAdapter(
        child: MenuGroupComponent(
          items: [
            MenuComponent(
              title: LibrarySharingStrings.librarySharing,
              subtitle: LibrarySharingStrings.shareAllYourAlbums,
              trailing: ToggleSwitchComponent(
                key: const ValueKey('library-sharing-toggle'),
                selected: false,
                optimisticallyUpdate: false,
                onChanged: (_) => _showEnableLibrarySharing(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _roleOverlay(BuildContext context, Collection album) {
    final role = _controller.activeRoleFor(album.id);
    return role == null ? null : LibrarySharingRoleBadge(role: role);
  }

  void _handleAlbumTap(Collection album) {
    if (_controller.isMutating) {
      return;
    }
    if (!_controller.isSelecting) {
      _controller.enterManageMode();
    }
    _controller.toggleSelection(album);
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (!_showSelectionSheet ||
        _controller.isMutating ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification.direction) {
      case ScrollDirection.reverse:
        _setSelectionSheetExpanded(false);
      case ScrollDirection.forward:
        _setSelectionSheetExpanded(true);
      case ScrollDirection.idle:
        break;
    }
    return false;
  }

  void _handleControllerChange() {
    final isVisible = _showSelectionSheet;
    if (isVisible && !_selectionSheetWasVisible) {
      _isSelectionSheetExpanded = true;
      _expandedSelectionSheetHeight = null;
    }
    _selectionSheetWasVisible = isVisible;
  }

  void _setSelectionSheetExpanded(bool isExpanded) {
    if (!mounted ||
        !_showSelectionSheet ||
        _isSelectionSheetExpanded == isExpanded) {
      return;
    }
    setState(() => _isSelectionSheetExpanded = isExpanded);
  }

  double get _gridBottomPadding {
    if (!_showSelectionSheet) {
      return Spacing.xxl;
    }
    return (_expandedSelectionSheetHeight ??
            _estimatedExpandedSelectionSheetHeight) +
        Spacing.md;
  }

  void _scheduleSelectionSheetMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSelectionSheet || !_isSelectionSheetExpanded) {
        return;
      }
      final renderObject = _selectionSheetKey.currentContext
          ?.findRenderObject();
      final height = renderObject is RenderBox
          ? renderObject.size.height
          : null;
      if (height == null ||
          (_expandedSelectionSheetHeight != null &&
              (height - _expandedSelectionSheetHeight!).abs() < 0.5)) {
        return;
      }
      setState(() => _expandedSelectionSheetHeight = height);
    });
  }

  double _titleBuilderHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return _scaledLineHeight(textScaler, _librarySharingEyebrowStyle) +
        _scaledLineHeight(textScaler, TextStyles.display2);
  }

  double _scaledLineHeight(TextScaler textScaler, TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    return textScaler.scale(fontSize) * (style.height ?? 1);
  }

  Future<void> _applySelection() async {
    await _showFailureIfNeeded(
      await _controller.applySelection(),
      _applySelection,
    );
  }

  Future<void> _stopSharing() async {
    final confirmed = await confirmStopLibrarySharing(
      context: context,
      count: _controller.selectedActiveShareCount,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final success = await _controller.stopSharingSelected();
    await _showFailureIfNeeded(success, _stopSharing);
  }

  Future<void> _showMixedRoles() async {
    final success = await showLibrarySharingRolesSheet(
      context: context,
      controller: _controller,
    );
    if (success != null) {
      await _showFailureIfNeeded(success, _applySelection);
    }
  }

  Future<void> _showEnableLibrarySharing() async {
    final shouldEnable = await showEnableLibrarySharingSheet(
      context: context,
      recipientLabel: _recipient.label,
    );
    if (shouldEnable && mounted) {
      showToastComponent(context, LibrarySharingStrings.comingSoon);
    }
  }

  Future<void> _showFailureIfNeeded(
    bool success,
    Future<void> Function() retry,
  ) async {
    if (!success && mounted) {
      await showLibrarySharingFailure(
        context: context,
        controller: _controller,
        onRetry: retry,
      );
    }
  }
}

/// Positions the 250px empty state group at the reference screen's y=287.
/// Source: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=17186-38829&m=dev
const double _fullLibraryEmptyStateTopPadding = 131;

/// The reference uses an Outfit Semibold 16/32 eyebrow above Display 2.
/// Source: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=15782-102259&m=dev
final TextStyle _librarySharingEyebrowStyle = TextStyles.display2.copyWith(
  fontSize: 16,
  height: 2,
);

// Prevents the final grid row from jumping under the sheet before measurement.
const double _estimatedExpandedSelectionSheetHeight = 320;
