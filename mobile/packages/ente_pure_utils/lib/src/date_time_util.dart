import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Set<int> monthWith31Days = {1, 3, 5, 7, 8, 10, 12};
const Set<int> monthWith30Days = {4, 6, 9, 11};
Map<int, String> _months = {
  1: "Jan",
  2: "Feb",
  3: "March",
  4: "April",
  5: "May",
  6: "Jun",
  7: "July",
  8: "Aug",
  9: "Sep",
  10: "Oct",
  11: "Nov",
  12: "Dec",
};
const Map<int, String> _shortMonths = {
  1: "Jan",
  2: "Feb",
  3: "Mar",
  4: "Apr",
  5: "May",
  6: "Jun",
  7: "Jul",
  8: "Aug",
  9: "Sep",
  10: "Oct",
  11: "Nov",
  12: "Dec",
};

Map<int, String> _fullMonths = {
  1: "January",
  2: "February",
  3: "March",
  4: "April",
  5: "May",
  6: "June",
  7: "July",
  8: "August",
  9: "September",
  10: "October",
  11: "November",
  12: "December",
};

Map<int, String> _days = {
  1: "Mon",
  2: "Tue",
  3: "Wed",
  4: "Thu",
  5: "Fri",
  6: "Sat",
  7: "Sun",
};

final currentYear = int.parse(DateTime.now().year.toString());
const searchStartYear = 1970;

String getMonthAndYear(DateTime dateTime) {
  return "${_months[dateTime.month]!} ${dateTime.year}";
}

String getDayAndMonth(DateTime dateTime) {
  return "${_days[dateTime.weekday]!}, ${dateTime.day} ${_months[dateTime.month]!}";
}

String getDateAndMonthAndYear(DateTime dateTime) {
  return "${dateTime.day} ${_months[dateTime.month]!}, ${dateTime.year}";
}

String getDay(DateTime dateTime) {
  return _days[dateTime.weekday]!;
}

String getMonth(DateTime dateTime) {
  return _months[dateTime.month]!;
}

String getFullMonth(DateTime dateTime) {
  return _fullMonths[dateTime.month]!;
}

String getAbbreviationOfYear(DateTime dateTime) {
  return (dateTime.year % 100).toString();
}

String getTime(DateTime dateTime) {
  final hours = dateTime.hour > 9
      ? dateTime.hour.toString()
      : "0${dateTime.hour}";
  final minutes = dateTime.minute > 9
      ? dateTime.minute.toString()
      : "0${dateTime.minute}";
  return "$hours:$minutes";
}

String getTimeIn12hrFormat(DateTime dateTime) {
  return DateFormat.jm().format(dateTime);
}

String getFormattedTime(
  DateTime dateTime, {
  BuildContext? context,
  bool withYear = false,
}) {
  if (context != null) {
    return DateFormat(
      'E, MMM d, y - HH:mm',
      Localizations.localeOf(context).languageCode,
    ).format(dateTime);
  }
  return "${getDay(dateTime)}, ${getMonth(dateTime)} ${dateTime.day}, ${dateTime.year} - ${getTime(dateTime)}";
}

String getFormattedDate(DateTime dateTime) {
  return "${dateTime.day} ${getMonth(dateTime)}'${getAbbreviationOfYear(dateTime)}";
}

String getFullDate(DateTime dateTime) {
  return "${getDay(dateTime)}, ${getMonth(dateTime)} ${dateTime.day} ${dateTime.year}";
}

String daysLeft(int futureTime) {
  final int daysLeft =
      ((futureTime - DateTime.now().microsecondsSinceEpoch) /
              Duration.microsecondsPerDay)
          .ceil();
  return '$daysLeft day${daysLeft <= 1 ? "" : "s"}';
}

String formatDuration(Duration position) {
  final ms = position.inMilliseconds;

  int seconds = ms ~/ 1000;
  final int hours = seconds ~/ 3600;
  seconds = seconds % 3600;
  final minutes = seconds ~/ 60;
  seconds = seconds % 60;

  final hoursString = hours >= 10
      ? '$hours'
      : hours == 0
      ? '00'
      : '0$hours';

  final minutesString = minutes >= 10
      ? '$minutes'
      : minutes == 0
      ? '00'
      : '0$minutes';

  final secondsString = seconds >= 10
      ? '$seconds'
      : seconds == 0
      ? '00'
      : '0$seconds';

  final formattedTime =
      '${hoursString == '00' ? '' : '$hoursString:'}$minutesString:$secondsString';

  return formattedTime;
}

bool isLeapYear(DateTime dateTime) {
  final year = dateTime.year;
  if (year % 4 == 0) {
    if (year % 100 == 0) {
      if (year % 400 == 0) {
        return true;
      } else {
        return false;
      }
    } else {
      return true;
    }
  } else {
    return false;
  }
}

String getDayTitle(int timestamp) {
  final date = DateTime.fromMicrosecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  var title = getDayAndMonth(date);
  if (date.year == now.year && date.month == now.month) {
    if (date.day == now.day) {
      title = "Today";
    } else if (date.day == now.day - 1) {
      title = "Yesterday";
    }
  }
  if (date.year != DateTime.now().year) {
    title += " ${date.year}";
  }
  return title;
}

String secondsToHHMMSS(int value) {
  int h, m, s;
  h = value ~/ 3600;
  m = ((value - h * 3600)) ~/ 60;
  s = value - (h * 3600) - (m * 60);
  final String hourLeft = h.toString().length < 2 ? "0$h" : h.toString();

  final String minuteLeft = m.toString().length < 2 ? "0$m" : m.toString();

  final String secondsLeft = s.toString().length < 2 ? "0$s" : s.toString();

  final String result = "$hourLeft:$minuteLeft:$secondsLeft";

  return result;
}

bool isValidDate({required int day, required int month, required int year}) {
  if (day < 0 || day > 31 || month < 0 || month > 12 || year < 0) {
    return false;
  }
  if (monthWith30Days.contains(month) && day > 30) {
    return false;
  }
  if (month == 2) {
    if (day > 29) {
      return false;
    }
    if (day == 29 && year % 4 != 0) {
      return false;
    }
  }
  return true;
}

Widget getDayWidget(
  BuildContext context,
  int timestamp,
  bool smallerTodayFont,
) {
  return Container(
    padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
    alignment: Alignment.centerLeft,
    child: Text(
      getDayTitle(timestamp),
      style: (getDayTitle(timestamp) == "Today" && !smallerTodayFont)
          ? Theme.of(context).textTheme.headlineSmall
          : Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter-SemiBold',
            ),
    ),
  );
}

bool areFromSameDay(int firstCreationTime, int secondCreationTime) {
  final firstDate = DateTime.fromMicrosecondsSinceEpoch(firstCreationTime);
  final secondDate = DateTime.fromMicrosecondsSinceEpoch(secondCreationTime);
  return firstDate.year == secondDate.year &&
      firstDate.month == secondDate.month &&
      firstDate.day == secondDate.day;
}

DateTime startOfISOWeek(DateTime date) {
  final mondayDay = date.day - (date.weekday - DateTime.monday);
  return date.isUtc
      ? DateTime.utc(date.year, date.month, mondayDay)
      : DateTime(date.year, date.month, mondayDay);
}

DateTime startOfNextISOWeek(DateTime date) {
  final start = startOfISOWeek(date);
  return start.isUtc
      ? DateTime.utc(start.year, start.month, start.day + 7)
      : DateTime(start.year, start.month, start.day + 7);
}

String getNameForDateRange(int firstCreationTime, int secondCreationTime) {
  final startTime = DateTime.fromMicrosecondsSinceEpoch(firstCreationTime);
  final endTime = DateTime.fromMicrosecondsSinceEpoch(secondCreationTime);
  if (startTime.year != endTime.year) {
    return "${_shortMonths[startTime.month]!} ${startTime.day}, ${startTime.year} - "
        "${_shortMonths[endTime.month]!} ${endTime.day}, ${endTime.year}";
  }
  if (startTime.month != endTime.month) {
    return "${_shortMonths[startTime.month]!} ${startTime.day} - "
        "${_shortMonths[endTime.month]!} ${endTime.day}, ${endTime.year}";
  }
  if (startTime.day != endTime.day) {
    return "${_shortMonths[startTime.month]!} ${startTime.day} - "
        "${_shortMonths[endTime.month]!} ${endTime.day}, ${endTime.year}";
  }
  return "${_shortMonths[endTime.month]!} ${endTime.day}, ${endTime.year}";
}

int? durationToSeconds(String? duration) {
  if (duration == null) {
    return null;
  }
  final parts = duration.split(':');
  int seconds = 0;

  if (parts.length == 3) {
    seconds += int.parse(parts[0]) * 3600;
    seconds += int.parse(parts[1]) * 60;
    seconds += int.parse(parts[2]);
  } else if (parts.length == 2) {
    seconds += int.parse(parts[0]) * 60;
    seconds += int.parse(parts[1]);
  } else {
    throw FormatException('Invalid duration format: $duration');
  }

  return seconds;
}

String secondsToDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

bool isValidGregorianDate({
  required int day,
  required int month,
  required int year,
}) {
  if (day <= 0 || day > 31 || month <= 0 || month > 12 || year < 0) {
    return false;
  }
  if ((month == 4 || month == 6 || month == 9 || month == 11) && day > 30) {
    return false;
  }
  if (month == 2) {
    if (day > 29) {
      return false;
    }
    if (day == 29 && (year % 4 != 0 || (year % 100 == 0 && year % 400 != 0))) {
      return false;
    }
  }
  return true;
}

final RegExp _filenameExp = RegExp('[\\.A-Za-z]*');

DateTime? parseDateTimeFromFileNameV2(
  String fileName, {
  // Year bounds reduce false dates parsed from filenames.
  int minYear = 1990,
  int? maxYear,
}) {
  // Include next year for 31 December edge cases.
  maxYear ??= currentYear + 1;
  String val = fileName.replaceAll(_filenameExp, '');
  if (val.isNotEmpty && !_isNumeric(val[0])) {
    val = val.substring(1, val.length);
  }
  if (val.isNotEmpty && !_isNumeric(val[val.length - 1])) {
    val = val.substring(0, val.length - 1);
  }
  final int countOfHyphen = val.split("-").length - 1;
  final int countUnderScore = val.split("_").length - 1;
  String valForParser = val;
  if (countOfHyphen == 1) {
    valForParser = val.replaceAll("-", "T");
  } else if (countUnderScore == 1 || countUnderScore == 2) {
    valForParser = val.replaceFirst("_", "T");
    if (countUnderScore == 2) {
      valForParser = valForParser.split("_")[0];
    }
  } else if (countOfHyphen == 2) {
    valForParser = val.replaceAll(".", ":");
  } else if (countOfHyphen == 6 || countOfHyphen == 7) {
    final splits = val.split("-");
    valForParser =
        "${splits[0]}${splits[1]}${splits[2]}T${splits[3]}${splits[4]}${splits[5]}";
  }
  final result = DateTime.tryParse(valForParser);
  if (result != null && result.year >= minYear && result.year <= maxYear) {
    return result;
  }
  return null;
}

bool _isNumeric(String? s) {
  if (s == null) {
    return false;
  }
  return double.tryParse(s) != null;
}
