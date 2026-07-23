import "package:intl/intl.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

enum TimeMemoryKind { day, month, week, lastWeek, lastMonth }

class TimeMemory extends SmartMemory {
  // For computing the title
  final TimeMemoryKind kind;
  DateTime? day;
  DateTime? month;
  int? yearsAgo;

  static TimeMemoryKind inferKind({DateTime? day, DateTime? month}) {
    if (day != null) {
      return TimeMemoryKind.day;
    }
    if (month != null) {
      return TimeMemoryKind.month;
    }
    return TimeMemoryKind.week;
  }

  TimeMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow, {
    String? id,
    this.day,
    this.month,
    this.yearsAgo,
    TimeMemoryKind? kind,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : kind = kind ?? inferKind(day: day, month: month),
       assert(
         kind != TimeMemoryKind.day || day != null,
         "day must be provided for day-based time memories",
       ),
       assert(
         kind != TimeMemoryKind.month || month != null,
         "month must be provided for month-based time memories",
       ),
       super(
         memories,
         MemoryType.time,
         '',
         firstDateToShow,
         lastDateToShow,
         id: id,
       );

  @override
  String createTitle(AppLocalizations locals, String languageCode) {
    switch (kind) {
      case TimeMemoryKind.day:
        final dayFormat = DateFormat.MMMd(languageCode).format(day!);
        if (yearsAgo != null) {
          return "$dayFormat, " + locals.yearsAgo(count: yearsAgo!);
        } else {
          return locals.throughTheYears(dateFormat: dayFormat);
        }
      case TimeMemoryKind.month:
        final monthFormat = DateFormat.MMMM(languageCode).format(month!);
        if (yearsAgo != null) {
          return "$monthFormat, " + locals.yearsAgo(count: yearsAgo!);
        } else {
          return locals.throughTheYears(dateFormat: monthFormat);
        }
      case TimeMemoryKind.week:
        if (yearsAgo != null) {
          return locals.thisWeekXYearsAgo(count: yearsAgo!);
        } else {
          return locals.thisWeekThroughTheYears;
        }
      case TimeMemoryKind.lastWeek:
        return locals.lastWeek;
      case TimeMemoryKind.lastMonth:
        return locals.lastMonth;
    }
  }
}
