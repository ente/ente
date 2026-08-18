import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/widgets.dart";
import "package:intl/intl.dart";
import "package:photos/models/file/file.dart";

enum GroupType { day, week, month, size, year, none }

extension GroupTypeExtension on GroupType {
  String get name {
    switch (this) {
      case GroupType.day:
        return "Day";
      case GroupType.week:
        return "Week";
      case GroupType.month:
        return "Month";
      case GroupType.size:
        return "Size";
      case GroupType.year:
        return "Year";
      case GroupType.none:
        return "None";
    }
  }

  String getLocalizedName(BuildContext context) {
    switch (this) {
      case GroupType.day:
        return context.strings.groupByDay;
      case GroupType.week:
        return context.strings.groupByWeek;
      case GroupType.month:
        return context.strings.groupByMonth;
      case GroupType.size:
        return "Size";
      case GroupType.year:
        return context.strings.groupByYear;
      case GroupType.none:
        return "None";
    }
  }

  bool timeGrouping() {
    return this == GroupType.day ||
        this == GroupType.week ||
        this == GroupType.month ||
        this == GroupType.year;
  }

  bool showGroupHeader() => timeGrouping();

  bool showScrollbarDivisions() => timeGrouping();

  String getTitle(BuildContext context, EnteFile file) {
    if (this == GroupType.day) {
      return _getDayTitle(context, file.creationTime!);
    } else if (this == GroupType.week) {
      return _getWeekTitle(context, file.creationTime!);
    } else if (this == GroupType.year) {
      return _getYearTitle(context, file.creationTime!);
    } else if (this == GroupType.month) {
      return _getMonthTitle(context, file.creationTime!);
    } else {
      throw UnimplementedError("getTitle not implemented for $this");
    }
  }

  bool areModifiedFilesPartOfGroup(
    List<EnteFile> modifiedFiles,
    EnteFile fistFile, {
    EnteFile? lastFile,
  }) {
    switch (this) {
      case GroupType.day:
        return modifiedFiles.any(
          (file) => areFromSameDay(fistFile.creationTime!, file.creationTime!),
        );
      case GroupType.week:
        return modifiedFiles.any((file) {
          final firstDate = DateTime.fromMicrosecondsSinceEpoch(
            fistFile.creationTime!,
          );
          final fileDate = DateTime.fromMicrosecondsSinceEpoch(
            file.creationTime!,
          );
          return areDatesInSameWeek(firstDate, fileDate);
        });
      case GroupType.month:
        return modifiedFiles.any((file) {
          final firstDate = DateTime.fromMicrosecondsSinceEpoch(
            fistFile.creationTime!,
          );
          final fileDate = DateTime.fromMicrosecondsSinceEpoch(
            file.creationTime!,
          );
          return firstDate.year == fileDate.year &&
              firstDate.month == fileDate.month;
        });
      case GroupType.year:
        return modifiedFiles.any((file) {
          final firstDate = DateTime.fromMicrosecondsSinceEpoch(
            fistFile.creationTime!,
          );
          final fileDate = DateTime.fromMicrosecondsSinceEpoch(
            file.creationTime!,
          );
          return firstDate.year == fileDate.year;
        });
      default:
        throw UnimplementedError("not implemented for $this");
    }
  }

  (int, int) getGroupRange(EnteFile file) {
    switch (this) {
      case GroupType.day:
        final date = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = DateTime(date.year, date.month, date.day + 1);
        return (
          startOfDay.microsecondsSinceEpoch,
          endOfDay.microsecondsSinceEpoch - 1,
        );
      case GroupType.week:
        final date = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
        final startOfWeek = DateTime(
          date.year,
          date.month,
          date.day,
        ).subtract(Duration(days: date.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return (
          startOfWeek.microsecondsSinceEpoch,
          endOfWeek.microsecondsSinceEpoch - 1,
        );
      case GroupType.month:
        final date = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
        final startOfMonth = DateTime(date.year, date.month);
        final endOfMonth = DateTime(date.year, date.month + 1);
        return (
          startOfMonth.microsecondsSinceEpoch,
          endOfMonth.microsecondsSinceEpoch - 1,
        );
      case GroupType.year:
        final date = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
        final startOfYear = DateTime(date.year);
        final endOfYear = DateTime(date.year + 1);
        return (
          startOfYear.microsecondsSinceEpoch,
          endOfYear.microsecondsSinceEpoch - 1,
        );
      default:
        throw UnimplementedError("not implemented for $this");
    }
  }

  bool areFromSameGroup(EnteFile first, EnteFile second) {
    switch (this) {
      case GroupType.day:
        return areFromSameDay(first.creationTime!, second.creationTime!);
      case GroupType.month:
        return DateTime.fromMicrosecondsSinceEpoch(first.creationTime!).year ==
                DateTime.fromMicrosecondsSinceEpoch(
                  second.creationTime!,
                ).year &&
            DateTime.fromMicrosecondsSinceEpoch(first.creationTime!).month ==
                DateTime.fromMicrosecondsSinceEpoch(second.creationTime!).month;
      case GroupType.year:
        return DateTime.fromMicrosecondsSinceEpoch(first.creationTime!).year ==
            DateTime.fromMicrosecondsSinceEpoch(second.creationTime!).year;
      case GroupType.week:
        final firstDate = DateTime.fromMicrosecondsSinceEpoch(
          first.creationTime!,
        );
        final secondDate = DateTime.fromMicrosecondsSinceEpoch(
          second.creationTime!,
        );
        return areDatesInSameWeek(firstDate, secondDate);
      default:
        throw UnimplementedError("not implemented for $this");
    }
  }

  String _getDayTitle(BuildContext context, int timestamp) {
    final date = DateTime.fromMicrosecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month) {
      if (date.day == now.day) {
        return context.strings.dayToday;
      } else if (date.day == now.day - 1) {
        return context.strings.dayYesterday;
      }
    }
    if (date.year != DateTime.now().year) {
      return DateFormat.yMMMEd(
        Localizations.localeOf(context).languageCode,
      ).format(date);
    } else {
      return DateFormat.MMMEd(
        Localizations.localeOf(context).languageCode,
      ).format(date);
    }
  }

  String _getWeekTitle(BuildContext context, int timestamp) {
    final date = DateTime.fromMicrosecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final nowStartOfWeek = now.subtract(Duration(days: now.weekday - 1));

    if (startOfWeek.year == nowStartOfWeek.year &&
        startOfWeek.month == nowStartOfWeek.month &&
        startOfWeek.day == nowStartOfWeek.day) {
      return context.strings.thisWeek;
    }

    final lastWeekStart = nowStartOfWeek.subtract(const Duration(days: 7));
    if (startOfWeek.year == lastWeekStart.year &&
        startOfWeek.month == lastWeekStart.month &&
        startOfWeek.day == lastWeekStart.day) {
      return context.strings.lastWeek;
    }

    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return "${DateFormat.MMMd(Localizations.localeOf(context).languageCode).format(startOfWeek)} - ${DateFormat.MMMd(Localizations.localeOf(context).languageCode).format(endOfWeek)}, ${endOfWeek.year}";
  }

  String _getMonthTitle(BuildContext context, int timestamp) {
    final date = DateTime.fromMicrosecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.year == now.year && date.month == now.month) {
      return context.strings.thisMonth;
    }

    return DateFormat.yMMM(
      Localizations.localeOf(context).languageCode,
    ).format(date);
  }

  String _getYearTitle(BuildContext context, int timestamp) {
    final date = DateTime.fromMicrosecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.year == now.year) {
      return context.strings.thisYear;
    }

    return DateFormat.y(
      Localizations.localeOf(context).languageCode,
    ).format(date);
  }
}
