import "package:ente_strings/ente_strings.dart";
import "package:intl/intl.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

DateTime wallClockOf(EnteFile file) {
  final captured = file.pubMagicMetadata?.dateTime;
  final wallClock = captured != null && captured.length >= 19
      ? DateTime.tryParse(captured.substring(0, 19))
      : null;
  return wallClock ??
      DateTime.fromMicrosecondsSinceEpoch(file.creationTime ?? 0);
}

int calendarDaysBetween(DateTime from, DateTime to) {
  return DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

sealed class SpecialMemory extends SmartMemory {
  final String shownKey;

  SpecialMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow,
    this.shownKey, {
    super.id,
  }) : super(memories, MemoryType.special, '', firstDateToShow, lastDateToShow);

  String get format;

  Map<String, dynamic> get details;

  bool get needsMl => formatNeedsMl(format);

  static bool formatNeedsMl(Object? format) {
    return format == ThenAndNowMemory.formatValue;
  }

  Map<String, dynamic> toJson() => {
    "format": format,
    "shownKey": shownKey,
    ...details,
  };

  static SpecialMemory? fromJson(
    Map<String, dynamic> json,
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String id,
  }) {
    final shownKey = json["shownKey"] as String?;
    if (shownKey == null) return null;
    return switch (json["format"]) {
      ThenAndNowMemory.formatValue => ThenAndNowMemory(
        memories,
        firstDateToShow,
        lastDateToShow,
        shownKey,
        id: id,
        locationName: json["locationName"] as String?,
        thenYear: json["thenYear"] as int,
        nowYear: json["nowYear"] as int,
        yearsApart: json["yearsApart"] as int,
      ),
      YearInAFlashMemory.formatValue => YearInAFlashMemory(
        memories,
        firstDateToShow,
        lastDateToShow,
        shownKey,
        id: id,
        year: json["year"] as int,
      ),
      OneDayMemory.formatValue => OneDayMemory(
        memories,
        firstDateToShow,
        lastDateToShow,
        shownKey,
        id: id,
        date: _dateFromJson(json["date"]),
        latitude: (json["latitude"] as num).toDouble(),
        longitude: (json["longitude"] as num).toDouble(),
        locationName: json["locationName"] as String?,
      ),
      _ => null,
    };
  }

  static List<int> _dateToJson(DateTime date) => [
    date.year,
    date.month,
    date.day,
  ];

  static DateTime _dateFromJson(dynamic json) {
    final parts = List<int>.from(json as List);
    return DateTime(parts[0], parts[1], parts[2]);
  }
}

class ThenAndNowMemory extends SpecialMemory {
  static const formatValue = "thenAndNow";

  final String? locationName;
  final int thenYear;
  final int nowYear;
  final int yearsApart;

  ThenAndNowMemory(
    super.memories,
    super.firstDateToShow,
    super.lastDateToShow,
    super.shownKey, {
    super.id,
    required this.locationName,
    required this.thenYear,
    required this.nowYear,
    required this.yearsApart,
  });

  Memory get then => memories.first;

  Memory get now => memories.last;

  @override
  bool get isShowable => memories.length == 2;

  @override
  String get format => formatValue;

  @override
  Map<String, dynamic> get details => {
    "locationName": locationName,
    "thenYear": thenYear,
    "nowYear": nowYear,
    "yearsApart": yearsApart,
  };

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    final place = locationName;
    return place == null
        ? locals.thenAndNow
        : locals.thenAndNowInPlace(place: place);
  }
}

class YearInAFlashMemory extends SpecialMemory {
  static const formatValue = "yearInAFlash";

  final int year;

  YearInAFlashMemory(
    super.memories,
    super.firstDateToShow,
    super.lastDateToShow,
    super.shownKey, {
    super.id,
    required this.year,
  });

  @override
  String get format => formatValue;

  @override
  Map<String, dynamic> get details => {"year": year};

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    return locals.yearInAFlash(year: year);
  }
}

class OneDayMemory extends SpecialMemory {
  static const formatValue = "oneDay";

  final DateTime date;
  final double latitude;
  final double longitude;
  final String? locationName;

  OneDayMemory(
    super.memories,
    super.firstDateToShow,
    super.lastDateToShow,
    super.shownKey, {
    super.id,
    required this.date,
    required this.latitude,
    required this.longitude,
    required this.locationName,
  });

  @override
  String get format => formatValue;

  @override
  Map<String, dynamic> get details => {
    "date": SpecialMemory._dateToJson(date),
    "latitude": latitude,
    "longitude": longitude,
    "locationName": locationName,
  };

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    final place = locationName;
    return place == null
        ? locals.oneDayInMonth(
            month: DateFormat.yMMMM(languageCode).format(date),
          )
        : locals.oneDayInPlace(place: place);
  }
}
