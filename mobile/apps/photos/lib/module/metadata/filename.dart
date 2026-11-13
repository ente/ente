import "package:ente_pure_utils/ente_pure_utils.dart";

final _filenameDate = RegExp(r'^[^\d]*(\d{4})([-.]?)(\d{2})\2(\d{2})(?!\d)');
final _filenameTime = RegExp(
  r'[ T_-](\d{2})([-.:]?)(\d{2})\2(\d{2})'
  r'(?:[.,](\d{1,6})(?!\d))?'
  r'([zZ]|\+\d{2}:?\d{2}|-\d{2}:\d{2})?(?!\d)',
);
final _filenameCompactOffset = RegExp(r'-\d+');
final _filenameDateSuffix = RegExp(
  r'(?:-WA\d+|[-_][A-Za-z]+)?(?:\.[A-Za-z][A-Za-z0-9]*)?$',
);
final _filenameTimeSuffix = RegExp(
  r'(?:[-_][A-Za-z0-9_.-]+|\.[A-Za-z][A-Za-z0-9_.-]*)?$',
);

DateTime? parseDateTimeFromFileName(
  String fileName, {
  // Year bounds reduce false dates parsed from filenames.
  int minYear = 1990,
  int? maxYear,
}) {
  final date = _filenameDate.matchAsPrefix(fileName);
  if (date == null) return null;

  final year = int.parse(date[1]!);
  final month = int.parse(date[3]!);
  final day = int.parse(date[4]!);
  if (year < minYear ||
      year > (maxYear ?? currentYear + 1) ||
      !isValidGregorianDate(day: day, month: month, year: year)) {
    return null;
  }

  final time = _filenameTime.matchAsPrefix(fileName, date.end);
  if (time == null) {
    // Don't turn an unrecognized time into a date-only result.
    return _filenameDateSuffix.matchAsPrefix(fileName, date.end) != null
        ? DateTime(year, month, day)
        : null;
  }
  var zone = time[6];
  var timeEnd = time.end;
  if (zone == null &&
      (fileName[date.end] == ' ' || fileName[date.end] == 'T')) {
    final offset = _filenameCompactOffset.matchAsPrefix(fileName, timeEnd);
    if (offset != null) {
      zone = offset[0];
      timeEnd = offset.end;
    }
  }
  if (_filenameTimeSuffix.matchAsPrefix(fileName, timeEnd) == null) {
    return null;
  }

  final hour = int.parse(time[1]!);
  final minute = int.parse(time[3]!);
  final second = int.parse(time[4]!);
  if (hour > 23 || minute > 59 || second > 59) return null;

  final fraction = time[5];
  final micros = fraction == null ? 0 : int.parse(fraction.padRight(6, '0'));
  if (zone == null) {
    return DateTime(year, month, day, hour, minute, second, 0, micros);
  }
  final utc = DateTime.utc(year, month, day, hour, minute, second, 0, micros);
  if (zone.length == 1) return utc;

  final offset = zone.substring(1).replaceAll(':', '');
  if (offset.length != 4) return null;
  final offsetHour = int.parse(offset.substring(0, 2));
  final offsetMinute = int.parse(offset.substring(2));
  if (offsetHour > 23 || offsetMinute > 59) return null;
  final offsetMinutes =
      (offsetHour * 60 + offsetMinute) * (zone[0] == '-' ? -1 : 1);
  return utc.subtract(Duration(minutes: offsetMinutes));
}
