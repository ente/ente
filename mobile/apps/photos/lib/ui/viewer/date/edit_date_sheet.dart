import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/date/date_time_picker.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/magic_util.dart";

Future<DateTime?> showEditDateSheet(
  BuildContext context,
  Iterable<EnteFile> enteFiles, {
  bool showHeader = true,
}) async {
  final newDate = await showModalBottomSheet<DateTime?>(
    context: context,
    isScrollControlled: true,
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

    final colorScheme = getEnteColorScheme(context);
    DateTime maxDate = DateTime.now();
    if (!selectSingleDate) {
      final maxForward = DateTime.now().difference(endDate);
      maxDate = startDate.add(maxForward);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Photo count and date range section
            if (widget.showHeader)
              PhotoDateHeaderWidget(
                enteFiles: widget.enteFiles,
                startDate: startDate,
                endDate: endDate,
              ),
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
              ),
            if (!showSingleOrShiftChoice &&
                !selectingDate &&
                !selectingTime &&
                selectedDate != startDate)
              Column(
                children: [
                  const SizedBox(height: 16),
                  ButtonWidget(
                    buttonType: ButtonType.primary,
                    labelText: AppLocalizations.of(context).confirm,
                    buttonSize: ButtonSize.large,
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
                  const SizedBox(height: 8),
                  ButtonWidget(
                    buttonType: ButtonType.neutral,
                    labelText: AppLocalizations.of(context).cancel,
                    buttonSize: ButtonSize.large,
                    onTap: () async {
                      Navigator.of(context).pop(null);
                    },
                  ),
                ],
              ),
            // Bottom indicator line
            const SizedBox(height: 20),
          ],
        ),
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
    final colorScheme = getEnteColorScheme(context);
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
                style: TextStyle(color: colorScheme.textBase, fontSize: 16),
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
                style: TextStyle(color: colorScheme.textFaint, fontSize: 12),
              ),
            ),
          if (!singleFile) const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.backgroundElevated2,
              border: Border.all(color: colorScheme.strokeFaint, width: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.calendar_today_outlined,
                    color: colorScheme.textBase,
                  ),
                  title: Text(
                    date,
                    style: TextStyle(color: colorScheme.textBase, fontSize: 16),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.strokeMuted,
                  ),
                  onTap: () => onPressedDate(),
                ),
                Divider(
                  color: colorScheme.blurStrokeFaint,
                  indent: 16,
                  endIndent: 16,
                  height: 0.5,
                ),
                ListTile(
                  leading: Icon(
                    Icons.access_time_outlined,
                    color: colorScheme.textBase,
                  ),
                  title: Text(
                    time,
                    style: TextStyle(color: colorScheme.textBase, fontSize: 16),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.strokeMuted,
                  ),
                  onTap: () => onPressedTime(),
                ),
              ],
            ),
          ),
          if (newRangeEnd != null) const SizedBox(height: 16),
          if (newRangeEnd != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context).newRange,
                style: TextStyle(color: colorScheme.textBase, fontSize: 12),
              ),
            ),
          if (newRangeEnd != null) const SizedBox(height: 8),
          if (newRangeEnd != null)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.backgroundElevated2,
                border: Border.all(color: colorScheme.strokeFaint, width: 0.5),
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
                        color: colorScheme.textBase,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(dateTime, locale, context),
                            style: TextStyle(
                              color: colorScheme.textFaint,
                              fontSize: 12,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "-",
                              style: TextStyle(
                                color: colorScheme.textFaint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            _formatDate(newRangeEnd!, locale, context),
                            style: TextStyle(
                              color: colorScheme.textFaint,
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
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.backgroundElevated2,
          border: Border.all(color: colorScheme.strokeFaint, width: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Select one date option
            ListTile(
              leading: Icon(
                Icons.calendar_today_outlined,
                color: colorScheme.textBase,
              ),
              title: Text(
                AppLocalizations.of(context).selectOneDateAndTime,
                style: TextStyle(color: colorScheme.textBase, fontSize: 16),
              ),
              subtitle: Text(
                AppLocalizations.of(context).moveSelectedPhotosToOneDate,
                style: TextStyle(color: colorScheme.textFaint, fontSize: 12),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: colorScheme.strokeMuted,
              ),
              onTap: () => onSelectOneDate(),
            ),
            Divider(
              color: colorScheme.blurStrokeFaint,
              indent: 16,
              endIndent: 16,
              height: 0.5,
            ),
            // Shift dates option
            ListTile(
              leading: Icon(
                Icons.calendar_month_outlined,
                color: colorScheme.textBase,
              ),
              title: Text(
                AppLocalizations.of(context).shiftDatesAndTime,
                style: TextStyle(color: colorScheme.textBase, fontSize: 16),
              ),
              subtitle: Text(
                AppLocalizations.of(context).photosKeepRelativeTimeDifference,
                style: TextStyle(color: colorScheme.textFaint, fontSize: 12),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: colorScheme.strokeMuted,
              ),
              onTap: () => onShiftDates(),
            ),
          ],
        ),
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
    final colorScheme = getEnteColorScheme(context);
    final locale = Localizations.localeOf(context);
    bool multipleFiles = true;
    if (photoCount == 1) {
      multipleFiles = false;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ThumbnailWidget(enteFiles.first),
            ),
          ),
          const SizedBox(width: 16),
          // Photo count and date info
          multipleFiles
              ? Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(
                          context,
                        ).photosCount(count: photoCount),
                        style: TextStyle(
                          color: colorScheme.textBase,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatDate(startDate, locale, context),
                            style: TextStyle(
                              color: colorScheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "-",
                              style: TextStyle(
                                color: colorScheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            _formatDate(endDate, locale, context),
                            style: TextStyle(
                              color: colorScheme.textMuted,
                              fontSize: 12,
                            ),
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
                      Padding(
                        padding: const EdgeInsets.only(right: 40),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            enteFiles.first.displayName,
                            style: TextStyle(
                              color: colorScheme.textBase,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${DateFormat.yMEd(locale.toString()).format(startDate)} · ${DateFormat(MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a').format(startDate)}",
                        style: TextStyle(
                          color: colorScheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date, Locale locale, BuildContext context) {
  return "${DateFormat.yMEd(locale.toString()).format(date)}\n${DateFormat(MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a').format(date)}";
}
