import "package:ente_components/ente_components.dart" as components;
import "package:ente_components/theme/text_styles.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:photos/core/constants.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/layout_settings.dart";

class GroupHeaderWidget extends StatefulWidget {
  final String title;
  final int gridSize;
  final double? height;
  final List<EnteFile> filesInGroup;
  final SelectedFiles? selectedFiles;
  final bool showSelectAll;
  final bool showGalleryLayoutSettingCTA;
  final bool showTrailingIcons;
  final bool isPinnedHeader;
  final bool fadeInTrailingIcons;

  const GroupHeaderWidget({
    super.key,
    required this.title,
    required this.gridSize,
    required this.filesInGroup,
    required this.selectedFiles,
    required this.showSelectAll,
    this.showGalleryLayoutSettingCTA = false,
    this.height,
    this.showTrailingIcons = true,
    this.isPinnedHeader = false,
    this.fadeInTrailingIcons = false,
  });

  @override
  State<GroupHeaderWidget> createState() => _GroupHeaderWidgetState();
}

class _GroupHeaderWidgetState extends State<GroupHeaderWidget> {
  static const _selectionIconSize = 18.0;

  late final ValueNotifier<bool> _areAllFromGroupSelectedNotifier;

  @override
  void initState() {
    super.initState();
    _areAllFromGroupSelectedNotifier = ValueNotifier(
      _areAllFromGroupSelected(),
    );

    widget.selectedFiles?.addListener(_selectedFilesListener);
  }

  @override
  void didUpdateWidget(covariant GroupHeaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _areAllFromGroupSelectedNotifier.value = _areAllFromGroupSelected();
    }
  }

  @override
  void dispose() {
    _areAllFromGroupSelectedNotifier.dispose();
    widget.selectedFiles?.removeListener(_selectedFilesListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final componentColors = components.ComponentTheme.colorsOf(context);
    const textStyle = TextStyles.body;
    final double horizontalPadding = widget.gridSize < photoGridSizeMax
        ? 12.0
        : 8.0;
    final double verticalPadding = widget.gridSize < photoGridSizeMax
        ? 12.0
        : 14.0;

    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Container(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                style:
                    (widget.title == AppLocalizations.of(context).dayToday ||
                        widget.title == AppLocalizations.of(context).thisWeek ||
                        widget.title ==
                            AppLocalizations.of(context).thisMonth ||
                        widget.title == AppLocalizations.of(context).thisYear)
                    ? textStyle
                    : textStyle.copyWith(color: colorScheme.textMuted),
                maxLines: 1,
                // TODO: Make it possible to see the full title if overflowing
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(child: Container()),
          !widget.showSelectAll
              ? const SizedBox.shrink()
              : widget.showTrailingIcons
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ValueListenableBuilder(
                      valueListenable: _areAllFromGroupSelectedNotifier,
                      builder: (context, dynamic value, _) {
                        return _buildSelectionIcon(value as bool);
                      },
                    ),
                  ),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.selectedFiles?.toggleGroupSelection(
                      widget.filesInGroup.toSet(),
                    );
                  },
                )
              : const SizedBox.shrink(),
          widget.showGalleryLayoutSettingCTA
              ? const SizedBox(width: 8)
              : const SizedBox.shrink(),
          widget.showGalleryLayoutSettingCTA
              ? widget.showTrailingIcons
                    ? GestureDetector(
                        onTap: () => _showLayoutSettingsOverflowMenu(context),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: widget.fadeInTrailingIcons
                              ? Icon(
                                  Icons.more_vert_outlined,
                                  // color: colorScheme.blurStrokeBase,
                                  color: componentColors.textLighter,
                                ).animate().fadeIn(
                                  duration: const Duration(
                                    milliseconds: PinnedGroupHeader
                                        .kTrailingIconsFadeInDurationMs,
                                  ),
                                  delay: const Duration(
                                    milliseconds:
                                        PinnedGroupHeader
                                            .kScaleDurationInMilliseconds +
                                        PinnedGroupHeader
                                            .kTrailingIconsFadeInDelayMs,
                                  ),
                                  curve: Curves.easeOut,
                                )
                              : Icon(
                                  Icons.more_vert_outlined,
                                  // color: colorScheme.blurStrokeBase,
                                  color: componentColors.textLighter,
                                ),
                        ),
                      )
                    : const SizedBox.shrink()
              : const SizedBox.shrink(),
          SizedBox(width: horizontalPadding - 4.0),
        ],
      ),
    );
  }

  void _selectedFilesListener() {
    if (widget.selectedFiles == null) return;
    // Filter out dummy files before checking selection state
    final nonDummyFiles = widget.filesInGroup
        .where((file) => file is! DummyFile)
        .toSet();
    _areAllFromGroupSelectedNotifier.value = widget.selectedFiles!.files
        .containsAll(nonDummyFiles);
  }

  Widget _buildSelectionIcon(bool isSelected) {
    final icon = SelectAllStatusIcon(
      isSelected: isSelected,
      size: _selectionIconSize,
      unselectedColor: components.ComponentTheme.colorsOf(context).textLighter,
    );
    if (!widget.fadeInTrailingIcons) {
      return icon;
    }

    return icon.animate().fadeIn(
      duration: const Duration(
        milliseconds: PinnedGroupHeader.kTrailingIconsFadeInDurationMs,
      ),
      delay: const Duration(
        milliseconds:
            PinnedGroupHeader.kScaleDurationInMilliseconds +
            PinnedGroupHeader.kTrailingIconsFadeInDelayMs,
      ),
      curve: Curves.easeOut,
    );
  }

  bool _areAllFromGroupSelected() {
    // Filter out dummy files before checking selection state
    final nonDummyFiles = widget.filesInGroup
        .where((file) => file is! DummyFile)
        .toSet();
    if (widget.selectedFiles != null &&
        widget.selectedFiles!.files.length >= nonDummyFiles.length) {
      return widget.selectedFiles!.files.containsAll(nonDummyFiles);
    } else {
      return false;
    }
  }

  void _showLayoutSettingsOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: getEnteColorScheme(context).backgroundElevated,
      builder: (BuildContext context) {
        return const GalleryLayoutSettings();
      },
    );
  }
}
