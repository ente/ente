import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:intl/intl.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/date/date_time_picker.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/magic_util.dart";

Future<DateTime?> showEditDateSheet(
  BuildContext context,
  Iterable<EnteFile> enteFiles, {
  bool showHeader = true,
}) async {
  final newDate = await showBottomSheetComponent<DateTime?>(
    context: context,
    builder: (context) =>
        EditDateSheet(enteFiles: enteFiles, showHeader: showHeader),
  );
  return newDate;
}

class EditDateSheet extends StatefulWidget {
  final Iterable<EnteFile> enteFiles;
  final bool showHeader;

  const EditDateSheet({
    super.key,
    required this.enteFiles,
    this.showHeader = true,
  });

  @override
  State<EditDateSheet> createState() => _EditDateSheetState();
}

class _EditDateSheetState extends State<EditDateSheet> {
  // Single date or shift date
  bool showSingleOrShiftChoice = false;
  bool selectSingleDate = false;

  bool selectingDate = false;
  bool selectingTime = false;

  late DateTime selectedDate;
  late DateTime startDate;
  late DateTime endDate;

  @override
  void initState() {
    super.initState();
    if (widget.enteFiles.length == 1) {
      selectSingleDate = true;
    } else if (widget.enteFiles.length > 1) {
      showSingleOrShiftChoice = true;
    }
    final firstFileTime = DateTime.fromMicrosecondsSinceEpoch(
      widget.enteFiles.first.creationTime!,
    );
    startDate = firstFileTime;
    endDate = firstFileTime;
    for (final file in widget.enteFiles) {
      if (file.creationTime == null) {
        continue;
      }
      final fileTime = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      if (fileTime.isBefore(startDate)) {
        startDate = fileTime;
      }
      if (fileTime.isAfter(endDate)) {
        endDate = fileTime;
      }
    }
    selectedDate = startDate;
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = widget.enteFiles.length;
    if (photoCount == 0) {
      return const SizedBox.shrink();
    }

    DateTime maxDate = DateTime.now();
    if (!selectSingleDate) {
      final maxForward = DateTime.now().difference(endDate);
      maxDate = startDate.add(maxForward);
    }
    final l10n = AppLocalizations.of(context);
    final String sheetTitle;
    if (selectingTime) {
      sheetTitle = l10n.selectTime;
    } else if (selectingDate) {
      sheetTitle = l10n.selectDate;
    } else {
      sheetTitle = l10n.editDateAndTime;
    }

    return BottomSheetComponent(
      title: sheetTitle,
      showCloseButton: true,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo count and date range section
          if (widget.showHeader)
            PhotoDateHeaderWidget(
              enteFiles: widget.enteFiles,
              startDate: startDate,
              endDate: endDate,
            ),
          if (widget.showHeader) const SizedBox(height: Spacing.lg),
          if (showSingleOrShiftChoice)
            SelectDateOrShiftWidget(
              onSelectOneDate: () {
                showSingleOrShiftChoice = false;
                selectSingleDate = true;
                setState(() {});
              },
              onShiftDates: () {
                showSingleOrShiftChoice = false;
                selectSingleDate = false;
                setState(() {});
              },
            ),
          if (!showSingleOrShiftChoice && !selectingDate && !selectingTime)
            DateAndTimeWidget(
              key: ValueKey(selectedDate.toString()),
              dateTime: selectedDate,
              selectDate: selectSingleDate,
              singleFile: photoCount == 1,
              newRangeEnd: (selectedDate != startDate && !selectSingleDate)
                  ? endDate.add(selectedDate.difference(startDate))
                  : null,
              onPressedDate: () {
                selectingDate = true;
                selectingTime = false;
                setState(() {});
              },
              onPressedTime: () {
                selectingDate = false;
                selectingTime = true;
                setState(() {});
              },
            ),
          if (selectingDate || selectingTime)
            DateTimePickerWidget(
              (DateTime dateTime) {
                selectedDate = dateTime;
                selectingDate = false;
                selectingTime = false;
                setState(() {});
              },
              () {
                selectingDate = false;
                selectingTime = false;
                setState(() {});
              },
              selectedDate,
              maxDateTime: maxDate,
              startWithTime: selectingTime,
              showTitle: false,
              onShowTimePickerChanged: (showTimePicker) {
                selectingDate = !showTimePicker;
                selectingTime = showTimePicker;
                setState(() {});
              },
            ),
          if (!showSingleOrShiftChoice &&
              !selectingDate &&
              !selectingTime &&
              selectedDate != startDate)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.lg),
              child: ButtonComponent(
                variant: ButtonComponentVariant.primary,
                size: ButtonComponentSize.large,
                label: AppLocalizations.of(context).confirm,
                onTap: () async {
                  final newDate = await _editDates(
                    context,
                    widget.enteFiles,
                    selectedDate,
                    selectSingleDate ? null : startDate,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(newDate);
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<DateTime> _editDates(
  BuildContext context,
  Iterable<EnteFile> enteFiles,
  DateTime newDate,
  DateTime? firstDateForShift,
) async {
  if (firstDateForShift != null) {
    final firstDateDiff = newDate.difference(firstDateForShift);
    final filesToNewDates = <EnteFile, int>{};
    for (final file in enteFiles) {
      if (file.creationTime == null) {
        continue;
      }
      final fileTime = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      final newTime = fileTime.add(firstDateDiff);
      filesToNewDates[file] = newTime.microsecondsSinceEpoch;
    }
    await editTime(context, filesToNewDates);
  } else {
    final filesToNewDates = <EnteFile, int>{};
    for (final file in enteFiles) {
      if (file.creationTime == null) {
        continue;
      }
      filesToNewDates[file] = newDate.microsecondsSinceEpoch;
    }
    await editTime(context, filesToNewDates);
  }
  return newDate;
}

class DateAndTimeWidget extends StatelessWidget {
  const DateAndTimeWidget({
    super.key,
    required this.dateTime,
    required this.selectDate,
    required this.onPressedDate,
    required this.onPressedTime,
    required this.singleFile,
    required this.newRangeEnd,
  });

  final DateTime dateTime;
  final bool selectDate;
  final bool singleFile;
  final DateTime? newRangeEnd;

  final Function() onPressedDate;
  final Function() onPressedTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final locale = Localizations.localeOf(context);
    final String date = DateFormat.yMMMd(locale.toString()).format(dateTime);
    final String time = DateFormat(
      MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a',
    ).format(dateTime);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (!singleFile)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectDate
                    ? AppLocalizations.of(context).selectOneDateAndTimeForAll
                    : AppLocalizations.of(context).selectStartOfRange,
                style: TextStyle(color: colors.textBase, fontSize: 16),
              ),
            ),
          if (!singleFile) const SizedBox(height: 8),
          if (!singleFile)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectDate
                    ? AppLocalizations.of(
                        context,
                      ).thisWillMakeTheDateAndTimeOfAllSelected
                    : AppLocalizations.of(
                        context,
                      ).allWillShiftRangeBasedOnFirst,
                style: TextStyle(color: colors.textLight, fontSize: 12),
              ),
            ),
          if (!singleFile) const SizedBox(height: 16),
          MenuGroupComponent(
            items: [
              MenuComponent(
                leading: HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendar04,
                  size: IconSizes.small,
                  color: colors.textLight,
                ),
                title: date,
                trailing: Icon(
                  Icons.chevron_right_outlined,
                  color: colors.textLight,
                  size: IconSizes.medium,
                ),
                onTap: () => onPressedDate(),
              ),
              MenuComponent(
                leading: HugeIcon(
                  icon: HugeIcons.strokeRoundedClock01,
                  size: IconSizes.small,
                  color: colors.textLight,
                ),
                title: time,
                trailing: Icon(
                  Icons.chevron_right_outlined,
                  color: colors.textLight,
                  size: IconSizes.medium,
                ),
                onTap: () => onPressedTime(),
              ),
            ],
          ),
          if (newRangeEnd != null) const SizedBox(height: 16),
          if (newRangeEnd != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context).newRange,
                style: TextStyle(color: colors.textBase, fontSize: 12),
              ),
            ),
          if (newRangeEnd != null) const SizedBox(height: 8),
          if (newRangeEnd != null)
            Container(
              decoration: BoxDecoration(
                color: colors.fillLight,
                border: Border.all(color: colors.strokeFaint, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.calendar_today_outlined,
                        color: colors.textBase,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(dateTime, locale, context),
                            style: TextStyle(
                              color: colors.textLight,
                              fontSize: 12,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "-",
                              style: TextStyle(
                                color: colors.textLight,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            _formatDate(newRangeEnd!, locale, context),
                            style: TextStyle(
                              color: colors.textLight,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (newRangeEnd != null) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class SelectDateOrShiftWidget extends StatelessWidget {
  const SelectDateOrShiftWidget({
    super.key,
    required this.onSelectOneDate,
    required this.onShiftDates,
  });

  final Function() onSelectOneDate;
  final Function() onShiftDates;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: MenuGroupComponent(
        items: [
          MenuComponent(
            leading: HugeIcon(
              icon: HugeIcons.strokeRoundedCalendar04,
              size: IconSizes.small,
              color: colors.textLight,
            ),
            title: AppLocalizations.of(context).selectOneDateAndTime,
            subtitle: AppLocalizations.of(context).moveSelectedPhotosToOneDate,
            trailing: Icon(
              Icons.chevron_right_outlined,
              color: colors.textLight,
              size: IconSizes.medium,
            ),
            onTap: () => onSelectOneDate(),
          ),
          MenuComponent(
            leading: HugeIcon(
              icon: HugeIcons.strokeRoundedCalendar03,
              size: IconSizes.small,
              color: colors.textLight,
            ),
            title: AppLocalizations.of(context).shiftDatesAndTime,
            subtitle: AppLocalizations.of(
              context,
            ).photosKeepRelativeTimeDifference,
            trailing: Icon(
              Icons.chevron_right_outlined,
              color: colors.textLight,
              size: IconSizes.medium,
            ),
            onTap: () => onShiftDates(),
          ),
        ],
      ),
    );
  }
}

class PhotoDateHeaderWidget extends StatelessWidget {
  const PhotoDateHeaderWidget({
    super.key,
    required this.enteFiles,
    required this.startDate,
    required this.endDate,
  });

  final Iterable<EnteFile> enteFiles;
  final DateTime startDate;
  final DateTime endDate;

  @override
  Widget build(BuildContext context) {
    final photoCount = enteFiles.length;
    final colors = context.componentColors;
    final locale = Localizations.localeOf(context);
    final bool multipleFiles = photoCount != 1;
    final dateTextStyle = TextStyles.mini.copyWith(color: colors.textLight);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: SizedBox(
            width: 56,
            height: 56,
            child: ThumbnailWidget(enteFiles.first),
          ),
        ),
        const SizedBox(width: Spacing.md),
        multipleFiles
            ? Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(
                        context,
                      ).photosCount(count: photoCount),
                      style: TextStyles.h2,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Row(
                      children: [
                        Text(
                          _formatDate(startDate, locale, context),
                          style: dateTextStyle,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm,
                          ),
                          child: Text("-", style: dateTextStyle),
                        ),
                        Text(
                          _formatDate(endDate, locale, context),
                          style: dateTextStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enteFiles.first.displayName,
                      style: TextStyles.h2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      "${DateFormat.yMEd(locale.toString()).format(startDate)} · ${DateFormat(MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a').format(startDate)}",
                      style: dateTextStyle,
                    ),
                  ],
                ),
              ),
      ],
    );
  }
}

String _formatDate(DateTime date, Locale locale, BuildContext context) {
  return "${DateFormat.yMEd(locale.toString()).format(date)}\n${DateFormat(MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a').format(date)}";
}
