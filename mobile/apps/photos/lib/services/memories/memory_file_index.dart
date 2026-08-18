part of "../smart_memories_service.dart";

typedef _CreationTimeRange = ({int start, int end});

class MemoryFileIndex {
  final List<EnteFile> files;
  final int _oldestYear;
  final int _newestYear;

  factory MemoryFileIndex(Iterable<EnteFile> source) {
    final files = source.toList();
    if (!_isCreationTimeDescending(files)) {
      final indexedFiles =
          <({EnteFile file, int position})>[
            for (var i = 0; i < files.length; i++)
              (file: files[i], position: i),
          ]..sort((a, b) {
            final timeCompare = b.file.creationTime!.compareTo(
              a.file.creationTime!,
            );
            return timeCompare != 0
                ? timeCompare
                : a.position.compareTo(b.position);
          });
      for (var i = 0; i < files.length; i++) {
        files[i] = indexedFiles[i].file;
      }
    }
    if (files.isEmpty) {
      return MemoryFileIndex._(files, 0, -1);
    }
    return MemoryFileIndex._(
      files,
      DateTime.fromMicrosecondsSinceEpoch(files.last.creationTime!).year,
      DateTime.fromMicrosecondsSinceEpoch(files.first.creationTime!).year,
    );
  }

  MemoryFileIndex._(this.files, this._oldestYear, this._newestYear);

  List<EnteFile> filesInDateRanges(
    Iterable<({DateTime start, DateTime end})> dateRanges,
  ) {
    return _filesInRanges(
      dateRanges.map(
        (range) => (
          start: range.start.microsecondsSinceEpoch,
          end: range.end.microsecondsSinceEpoch,
        ),
      ),
    );
  }

  List<EnteFile> filesForCalendar({
    Set<int> monthDays = const <int>{},
    int? month,
    int? week,
  }) {
    if (files.isEmpty) return <EnteFile>[];

    final yearCount = _newestYear - _oldestYear + 1;
    if (yearCount <= 0 || yearCount > files.length) {
      return files;
    }

    final ranges = <_CreationTimeRange>[];
    for (var year = _oldestYear; year <= _newestYear; year++) {
      for (final monthDay in monthDays) {
        final candidateMonth = monthDay ~/ 100;
        final candidateDay = monthDay % 100;
        final start = DateTime(year, candidateMonth, candidateDay);
        if (start.year != year ||
            start.month != candidateMonth ||
            start.day != candidateDay) {
          continue;
        }
        ranges.add((
          start: start.microsecondsSinceEpoch,
          end: DateTime(
            year,
            candidateMonth,
            candidateDay + 1,
          ).microsecondsSinceEpoch,
        ));
      }

      if (month != null) {
        ranges.add((
          start: DateTime(year, month).microsecondsSinceEpoch,
          end: DateTime(year, month + 1).microsecondsSinceEpoch,
        ));
      }

      if (week != null) {
        final start = DateTime(year, 1, 1 + (week - 1) * 7);
        if (start.year == year) {
          final weekEnd = DateTime(year, 1, 1 + week * 7);
          final yearEnd = DateTime(year + 1);
          ranges.add((
            start: start.microsecondsSinceEpoch,
            end: min(
              weekEnd.microsecondsSinceEpoch,
              yearEnd.microsecondsSinceEpoch,
            ),
          ));
        }
      }
    }
    return _filesInRanges(ranges);
  }

  List<EnteFile> _filesInRanges(Iterable<_CreationTimeRange> sourceRanges) {
    final ranges =
        sourceRanges.where((range) => range.start < range.end).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    if (ranges.isEmpty) return <EnteFile>[];

    final merged = <_CreationTimeRange>[];
    var current = ranges.first;
    for (final next in ranges.skip(1)) {
      if (next.start <= current.end) {
        current = (start: current.start, end: max(current.end, next.end));
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    final result = <EnteFile>[];
    for (final range in merged.reversed) {
      final firstIndex = _firstFileCreatedBefore(range.end);
      final endIndex = _firstFileCreatedBefore(range.start);
      result.addAll(files.getRange(firstIndex, endIndex));
    }
    return result;
  }

  int _firstFileCreatedBefore(int timestamp) {
    var low = 0;
    var high = files.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (files[middle].creationTime! >= timestamp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static bool _isCreationTimeDescending(List<EnteFile> files) {
    for (var i = 1; i < files.length; i++) {
      if (files[i - 1].creationTime! < files[i].creationTime!) {
        return false;
      }
    }
    return true;
  }
}
