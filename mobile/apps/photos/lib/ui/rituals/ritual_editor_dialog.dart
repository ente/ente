import "dart:io";

import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/album/column_item.dart";
import "package:photos/ui/collections/album/new_list_item.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/dialog_util.dart";

Future<void> showRitualEditor(BuildContext context, {Ritual? ritual}) async {
  await _showRitualEditor(context, ritual: ritual);
}

Future<void> _showRitualEditor(BuildContext context, {Ritual? ritual}) async {
  final controller = TextEditingController(text: ritual?.title ?? "");
  final titleFocusNode = FocusNode();
  bool titleFocusNodeDisposed = false;
  double lastKeyboardInset = 0;
  final days = [...(ritual?.daysOfWeek ?? List<bool>.filled(7, true))];
  Collection? selectedAlbum = ritual?.albumId != null
      ? CollectionsService.instance.getCollectionByID(ritual!.albumId!)
      : null;
  String? selectedAlbumName = selectedAlbum?.displayName ?? ritual?.albumName;
  int? selectedAlbumId = selectedAlbum?.id ?? ritual?.albumId;
  TimeOfDay selectedTime =
      ritual?.timeOfDay ?? const TimeOfDay(hour: 9, minute: 0);
  String selectedEmoji = ritual?.icon ?? "📸";
  final formKey = GlobalKey<FormState>();
  bool sendReminderEnabled = ritual?.remindersEnabled ?? true;

  try {
    await showGeneralDialog(
      context: context,
      barrierLabel: context.l10n.ritualEditorLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 240),
      useRootNavigator: false,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final keyboardInset = mediaQuery.viewInsets.bottom;
        if (lastKeyboardInset > 0 &&
            keyboardInset == 0 &&
            titleFocusNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (titleFocusNodeDisposed) return;
            if (titleFocusNode.hasFocus) {
              titleFocusNode.unfocus();
            }
          });
        }
        lastKeyboardInset = keyboardInset;
        final colorScheme = getEnteColorScheme(dialogContext);
        final textTheme = getEnteTextTheme(dialogContext);
        final bottomPadding = mediaQuery.viewPadding.bottom;
        final maxHeight = mediaQuery.size.height * 0.95;
        return MediaQuery.removeViewInsets(
          context: dialogContext,
          removeBottom: true,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding + 16),
                  child: Material(
                    color: Colors.transparent,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        final bool canSave =
                            controller.text.trim().isNotEmpty &&
                            selectedAlbumId != null;
                        final bool allDaysOff = days.every(
                          (selected) => !selected,
                        );
                        final widgetBackgroundColor =
                            colorScheme.backgroundElevated2;
                        final segmentedBackgroundColor = colorScheme.fillFaint;
                        final localizations = MaterialLocalizations.of(
                          dialogContext,
                        );
                        final bool use24HourFormat = MediaQuery.of(
                          context,
                        ).alwaysUse24HourFormat;
                        final int hour12 = selectedTime.hourOfPeriod == 0
                            ? 12
                            : selectedTime.hourOfPeriod;
                        final String hourText = use24HourFormat
                            ? selectedTime.hour.toString().padLeft(2, "0")
                            : hour12.toString();
                        final String minuteText = selectedTime.minute
                            .toString()
                            .padLeft(2, "0");
                        final String? periodText = use24HourFormat
                            ? null
                            : (selectedTime.period == DayPeriod.am
                                  ? localizations.anteMeridiemAbbreviation
                                  : localizations.postMeridiemAbbreviation);
                        final timeTextStyle = textTheme.large.copyWith(
                          fontWeight: FontWeight.w400,
                        );

                        Widget timeSegment(
                          String text, {
                          required TextStyle style,
                        }) {
                          return Container(
                            width: 64,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: segmentedBackgroundColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(child: Text(text, style: style)),
                          );
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: colorScheme.backgroundElevated,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 22,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: Form(
                              key: formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        ritual == null
                                            ? context.l10n.ritualCreateNewTitle
                                            : context.l10n.ritualEdit,
                                        style: textTheme.largeBold,
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 70,
                                            height: 70,
                                            decoration: BoxDecoration(
                                              color: widgetBackgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Center(
                                              child: Text(
                                                selectedEmoji,
                                                style: const TextStyle(
                                                  fontSize: 32,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: -4,
                                            bottom: -4,
                                            child: Material(
                                              color: colorScheme
                                                  .backgroundElevated,
                                              shape: const CircleBorder(),
                                              elevation: 2,
                                              child: InkWell(
                                                customBorder:
                                                    const CircleBorder(),
                                                onTap: () async {
                                                  final emoji =
                                                      await _pickEmoji(
                                                        context,
                                                        selectedEmoji,
                                                      );
                                                  if (emoji != null) {
                                                    setState(() {
                                                      selectedEmoji = emoji;
                                                    });
                                                  }
                                                },
                                                child: const Padding(
                                                  padding: EdgeInsets.all(6),
                                                  child: HugeIcon(
                                                    icon: HugeIcons
                                                        .strokeRoundedEdit03,
                                                    size: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: controller,
                                          focusNode: titleFocusNode,
                                          autofocus: false,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            hintText:
                                                context.l10n.ritualEnterPrompt,
                                            hintStyle: textTheme.body.copyWith(
                                              color: const Color(0xFF969696),
                                            ),
                                            filled: true,
                                            fillColor: widgetBackgroundColor,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 14,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide.none,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return context
                                                  .l10n
                                                  .ritualEnterDescription;
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 28),
                                  _sectionLabel(
                                    context,
                                    context.l10n.ritualChooseDaysLabel,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widgetBackgroundColor,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        const double maxCircleSize = 38;
                                        const double minCircleSize = 20;
                                        const double minSpacing = 6;
                                        final double availableWidth =
                                            constraints.maxWidth;

                                        double circleSize = maxCircleSize;
                                        double spacing =
                                            (availableWidth - circleSize * 7) /
                                            8;

                                        if (spacing < minSpacing) {
                                          spacing = minSpacing;
                                          circleSize =
                                              ((availableWidth -
                                                          (spacing * 8)) /
                                                      7)
                                                  .clamp(
                                                    minCircleSize,
                                                    maxCircleSize,
                                                  );
                                          spacing =
                                              (availableWidth -
                                                  circleSize * 7) /
                                              8;
                                        }

                                        final children = <Widget>[
                                          SizedBox(width: spacing),
                                        ];
                                        for (
                                          int index = 0;
                                          index < days.length;
                                          index++
                                        ) {
                                          children.add(
                                            _DayCircle(
                                              label: _weekLabel(context, index),
                                              selected: days[index],
                                              size: circleSize,
                                              colorScheme: colorScheme,
                                              onTap: () {
                                                setState(() {
                                                  days[index] = !days[index];
                                                });
                                              },
                                            ),
                                          );
                                          children.add(
                                            SizedBox(width: spacing),
                                          );
                                        }

                                        return Row(children: children);
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _sectionLabel(
                                    context,
                                    context.l10n.ritualChooseAlbumLabel,
                                  ),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      final result = await _pickAlbum(context);
                                      if (result != null) {
                                        setState(() {
                                          selectedAlbum = result;
                                          selectedAlbumId = result.id;
                                          selectedAlbumName =
                                              result.displayName;
                                        });
                                      }
                                    },
                                    child: _AlbumPreviewTile(
                                      album: selectedAlbum,
                                      fallbackName: selectedAlbumName,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (allDaysOff)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: widgetBackgroundColor,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.notifications_off_outlined,
                                            color: colorScheme.textMuted,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              context
                                                  .l10n
                                                  .ritualNotificationsOffHint,
                                              style: textTheme.small.copyWith(
                                                color: colorScheme.textMuted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    Row(
                                      children: [
                                        _sectionLabel(
                                          context,
                                          context.l10n.ritualSendReminderLabel,
                                        ),
                                        const Spacer(),
                                        CupertinoSwitch(
                                          value: sendReminderEnabled,
                                          activeTrackColor:
                                              colorScheme.primary500,
                                          onChanged: (value) {
                                            setState(() {
                                              sendReminderEnabled = value;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    if (sendReminderEnabled) ...[
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () async {
                                          final result = await showTimePicker(
                                            context: context,
                                            initialTime: selectedTime,
                                            builder: (context, child) {
                                              if (child == null) {
                                                return const SizedBox.shrink();
                                              }
                                              final mediaQuery = MediaQuery.of(
                                                context,
                                              );
                                              return MediaQuery(
                                                data: mediaQuery.copyWith(
                                                  alwaysUse24HourFormat:
                                                      use24HourFormat,
                                                ),
                                                child: child,
                                              );
                                            },
                                          );
                                          if (result != null) {
                                            setState(() {
                                              selectedTime = result;
                                            });
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: widgetBackgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  timeSegment(
                                                    hourText,
                                                    style: timeTextStyle,
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Text(
                                                    ":",
                                                    style: timeTextStyle,
                                                  ),
                                                  const SizedBox(width: 9),
                                                  timeSegment(
                                                    minuteText,
                                                    style: timeTextStyle,
                                                  ),
                                                  if (periodText != null) ...[
                                                    const SizedBox(width: 9),
                                                    timeSegment(
                                                      periodText,
                                                      style: timeTextStyle,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      segmentedBackgroundColor,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  Icons.schedule,
                                                  color: colorScheme.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: canSave
                                            ? colorScheme.primary500
                                            : colorScheme.fillMuted,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 18,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        side: BorderSide.none,
                                        elevation: 0,
                                      ),
                                      onPressed: canSave
                                          ? () async {
                                              final updated =
                                                  (ritual ??
                                                          ritualsService
                                                              .createEmptyRitual())
                                                      .copyWith(
                                                        title: controller.text
                                                            .trim(),
                                                        daysOfWeek: days,
                                                        timeOfDay: selectedTime,
                                                        remindersEnabled:
                                                            sendReminderEnabled,
                                                        albumId:
                                                            selectedAlbumId,
                                                        albumName:
                                                            selectedAlbumName,
                                                        icon: selectedEmoji,
                                                      );
                                              await ritualsService.saveRitual(
                                                updated,
                                              );
                                              if (!context.mounted) return;
                                              Navigator.of(context).pop();
                                            }
                                          : null,
                                      child: Text(
                                        ritual == null
                                            ? context.l10n.ritualCreateAction
                                            : context.l10n.ritualUpdate,
                                        style: textTheme.bodyBold.copyWith(
                                          color: canSave
                                              ? Colors.white
                                              : colorScheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  } finally {
    titleFocusNodeDisposed = true;
    titleFocusNode.dispose();
    controller.dispose();
  }
}

String _weekLabel(BuildContext context, int index) {
  final labels = MaterialLocalizations.of(context).narrowWeekdays;
  return labels[index % labels.length];
}

Future<Collection?> _pickAlbum(BuildContext context) async {
  final albums = List<Collection>.from(
    await CollectionsService.instance.getCollectionsForRituals(),
  );
  Collection? selected;

  if (!context.mounted) return null;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _AlbumPickerSheet(
        albums: albums,
        onSelected: (collection) => selected = collection,
      );
    },
  );

  return selected;
}

class _AlbumPickerSheet extends StatefulWidget {
  const _AlbumPickerSheet({required this.albums, required this.onSelected});

  final List<Collection> albums;
  final ValueChanged<Collection?> onSelected;

  @override
  State<_AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends State<_AlbumPickerSheet> {
  late final TextEditingController _controller;
  Collection? _selected;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = CollectionsService.instance;
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = context.l10n;
    final trimmedQuery = _controller.text.trim();
    final bool showNewAlbumRow = trimmedQuery.isEmpty;
    final queryLower = trimmedQuery.toLowerCase();
    final filteredAlbums = queryLower.isEmpty
        ? widget.albums
        : widget.albums
              .where(
                (album) => album.displayName.toLowerCase().contains(queryLower),
              )
              .toList();

    Future<void> createAlbum() async {
      Collection? created;
      final result = await showTextInputDialog(
        context,
        title: l10n.albumTitle,
        submitButtonLabel: l10n.ok,
        hintText: l10n.enterAlbumName,
        onSubmit: (name) async {
          final trimmedName = name.trim();
          if (trimmedName.isEmpty) return;
          created = await service.createAlbum(trimmedName);
        },
        showOnlyLoadingState: true,
        textCapitalization: TextCapitalization.words,
        popnavAfterSubmission: true,
      );
      if (!context.mounted) return;
      if (result is Exception) {
        await showGenericErrorDialog(context: context, error: result);
        return;
      }
      if (created == null) return;
      if (!context.mounted) return;
      _selected = created;
      widget.onSelected(created);
      Navigator.of(context).pop();
    }

    final newAlbumRow = NewAlbumListItemWidget(onTap: (_) => createAlbum());

    Widget buildEmptyState() {
      final message = widget.albums.isEmpty
          ? l10n.ritualNoAlbumsYet
          : l10n.ritualNoMatchingAlbums;
      if (!showNewAlbumRow) {
        return Center(
          child: Text(
            message,
            style: textTheme.small.copyWith(color: colorScheme.textMuted),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          newAlbumRow,
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: Text(
                message,
                style: textTheme.small.copyWith(color: colorScheme.textMuted),
              ),
            ),
          ),
        ],
      );
    }

    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: mediaQuery.viewPadding.bottom + 16,
            top: 8,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.backgroundElevated,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        l10n.ritualSelectAlbumTitle,
                        style: textTheme.bodyBold,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: l10n.searchByAlbumNameHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: colorScheme.fillFaint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                ),
                Flexible(
                  child: SizedBox(
                    height: 360,
                    child: filteredAlbums.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: buildEmptyState(),
                          )
                        : ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemBuilder: (context, index) {
                              if (showNewAlbumRow && index == 0) {
                                return newAlbumRow;
                              }
                              final albumIndex =
                                  index - (showNewAlbumRow ? 1 : 0);
                              final album = filteredAlbums[albumIndex];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _selected = album;
                                  widget.onSelected(album);
                                  Navigator.of(context).pop();
                                },
                                child: AlbumColumnItemWidget(
                                  album,
                                  selectedCollections: _selected == album
                                      ? <Collection>[album]
                                      : const <Collection>[],
                                ),
                              );
                            },
                            separatorBuilder: (_, _) => const SizedBox(
                              height: ThumbnailListItem.defaultItemSpacing,
                            ),
                            itemCount:
                                filteredAlbums.length +
                                (showNewAlbumRow ? 1 : 0),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumPreviewTile extends StatelessWidget {
  const _AlbumPreviewTile({required this.album, required this.fallbackName});

  final Collection? album;
  final String? fallbackName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final displayedName =
        album?.displayName ??
        fallbackName ??
        context.l10n.ritualAlbumSelectionPlaceholder;
    final isPlaceholder =
        album == null && (fallbackName == null || fallbackName!.trim().isEmpty);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _AlbumThumbnail(album: album),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.ritualAlbumLabel, style: textTheme.miniMuted),
                const SizedBox(height: 2),
                Text(
                  displayedName,
                  style: textTheme.smallBold.copyWith(
                    color: isPlaceholder ? const Color(0xFF969696) : null,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colorScheme.textMuted),
        ],
      ),
    );
  }
}

class _AlbumThumbnail extends StatelessWidget {
  const _AlbumThumbnail({required this.album});

  final Collection? album;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    if (album == null) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: colorScheme.fillFaintPressed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.photo_album_outlined, color: colorScheme.textMuted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 60,
        height: 60,
        child: FutureBuilder<EnteFile?>(
          future: CollectionsService.instance.getCover(album!),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return ThumbnailWidget(
                snapshot.data!,
                showFavForAlbumOnly: true,
                shouldShowOwnerAvatar: false,
              );
            }
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.fillFaintPressed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.photo_album_outlined,
                color: colorScheme.textMuted,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.label,
    required this.selected,
    required this.size,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double size;
  final EnteColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary500 : colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colorScheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _sectionLabel(BuildContext context, String label) {
  final textTheme = getEnteTextTheme(context);
  return Text(
    label,
    style: textTheme.small.copyWith(
      color: const Color(0xFF666666),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );
}

const List<String> _emojiOptions = [
  "📸",
  "😊",
  "💪",
  "☕️",
  "🌅",
  "🏃",
  "🧘",
  "📚",
  "🏋️",
  "💅",
  "🎨",
  "🥾",
  "🌙",
  "📝",
  "🧠",
  "🧹",
  "🌻",
  "🧩",
];

Future<String?> _pickEmoji(BuildContext context, String current) async {
  final colorScheme = getEnteColorScheme(context);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: colorScheme.backgroundElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _EmojiPickerSheet(initialEmoji: current),
  );
}

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet({required this.initialEmoji});

  final String initialEmoji;

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  late final TextEditingController _customEmojiController;
  late final FocusNode _customEmojiFocusNode;
  late String _customEmoji;
  bool _didPop = false;
  bool _isUpdatingController = false;
  bool _didClearOnFocus = false;

  @override
  void initState() {
    super.initState();
    _customEmoji = widget.initialEmoji;
    _customEmojiController = TextEditingController(text: widget.initialEmoji);
    _customEmojiFocusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _customEmojiFocusNode.dispose();
    _customEmojiController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!Platform.isIOS ||
        !_customEmojiFocusNode.hasFocus ||
        _didClearOnFocus ||
        _didPop) {
      return;
    }
    _didClearOnFocus = true;
    if (_customEmojiController.text.isEmpty) return;
    _customEmoji = "";
    _isUpdatingController = true;
    _customEmojiController.value = const TextEditingValue(
      text: "",
      selection: TextSelection.collapsed(offset: 0),
    );
    _isUpdatingController = false;
    setState(() {});
  }

  void _popWithEmoji(String emoji) {
    if (_didPop) return;
    _didPop = true;
    Navigator.of(context).pop(emoji);
  }

  void _handleChanged(String value) {
    if (_isUpdatingController || _didPop) return;
    final trimmed = value.trim();
    final firstGrapheme = trimmed.characters.isEmpty
        ? ""
        : trimmed.characters.take(1).toString();
    if (firstGrapheme.isEmpty) {
      _customEmoji = "";
      _isUpdatingController = true;
      _customEmojiController.value = const TextEditingValue(
        text: "",
        selection: TextSelection.collapsed(offset: 0),
      );
      _isUpdatingController = false;
      setState(() {});
      return;
    }
    if (!_isEmoji(firstGrapheme)) {
      _isUpdatingController = true;
      _customEmojiController.value = TextEditingValue(
        text: _customEmoji,
        selection: TextSelection.collapsed(offset: _customEmoji.length),
      );
      _isUpdatingController = false;
      return;
    }
    _customEmoji = firstGrapheme;
    _isUpdatingController = true;
    _customEmojiController.value = TextEditingValue(
      text: firstGrapheme,
      selection: TextSelection.collapsed(offset: firstGrapheme.length),
    );
    _isUpdatingController = false;
    _popWithEmoji(firstGrapheme);
  }

  void _handleSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !_isEmoji(trimmed)) return;
    _popWithEmoji(trimmed.characters.take(1).toString());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.l10n.ritualPickEmojiTitle,
                  style: textTheme.bodyBold,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              childAspectRatio: 1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: _emojiOptions.map((emoji) {
                final isActive = emoji == _customEmoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _popWithEmoji(emoji),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive
                          ? colorScheme.primary500.withValues(alpha: 0.1)
                          : colorScheme.fillFaint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? colorScheme.primary500
                            : colorScheme.strokeFaint,
                      ),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.ritualCustomKeyboardLabel,
              style: textTheme.miniMuted,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customEmojiController,
                    focusNode: _customEmojiFocusNode,
                    textInputAction: TextInputAction.done,
                    onTap: () {
                      final text = _customEmojiController.text;
                      _customEmojiController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: text.length,
                      );
                    },
                    onChanged: _handleChanged,
                    onSubmitted: _handleSubmitted,
                    decoration: InputDecoration(
                      hintText: context.l10n.ritualEmojiKeyboardHint,
                      filled: true,
                      fillColor: colorScheme.fillFaint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.strokeFaint),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary500,
                    minimumSize: const Size(64, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _customEmoji.isEmpty
                      ? null
                      : () => _popWithEmoji(_customEmoji),
                  child: Text(
                    context.l10n.ritualEmojiUseAction,
                    style: textTheme.bodyBold.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool _isEmoji(String value) {
  if (value.isEmpty) return false;
  final codePoints = value.runes;
  for (final codePoint in codePoints) {
    if ((codePoint >= 0x1F300 && codePoint <= 0x1FAFF) ||
        (codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF) ||
        (codePoint >= 0x1F680 && codePoint <= 0x1F6FF) ||
        (codePoint >= 0x2600 && codePoint <= 0x27BF)) {
      return true;
    }
  }
  return false;
}
