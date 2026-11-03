import "dart:ui";

import "package:icu4x/icu4x.dart" as icu;
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";

icu.Collator? _collator;
String? _collatorLocale;

icu.Collator _filenameCollator(String? localeTag) {
  final tag = localeTag ?? PlatformDispatcher.instance.locale.toLanguageTag();
  if (_collator == null || _collatorLocale != tag) {
    final locale = icu.Locale.fromString(tag)
      ..setUnicodeExtension("kn", "true");
    _collator = icu.Collator(
      locale,
      icu.CollatorOptions(
        strength: icu.CollatorStrength.primary,
        caseLevel: icu.CollatorCaseLevel.off,
        alternateHandling: icu.CollatorAlternateHandling.nonIgnorable,
      ),
    );
    _collatorLocale = tag;
  }
  return _collator!;
}

int _compareFileIDs(EnteFile first, EnteFile second) {
  return (first.uploadedFileID ?? first.generatedID ?? 0).compareTo(
    second.uploadedFileID ?? second.generatedID ?? 0,
  );
}

void sortFilesByName(
  List<EnteFile> files,
  FileSortOrder order, {
  String? localeTag,
}) {
  assert(order.isFilename);
  if (files.length < 2) return;
  final entries = files.map(_FilenameSortEntry.new).toList();
  entries.sort(_filenameComparator(order, localeTag));
  for (var index = 0; index < entries.length; index++) {
    files[index] = entries[index].file;
  }
}

EnteFile? firstFileByName(
  List<EnteFile> files,
  FileSortOrder order, {
  String? localeTag,
}) {
  assert(order.isFilename);
  if (files.length < 2) return files.firstOrNull;
  final compare = _filenameComparator(order, localeTag);
  var first = _FilenameSortEntry(files.first);
  for (var index = 1; index < files.length; index++) {
    final candidate = _FilenameSortEntry(files[index]);
    if (compare(candidate, first) < 0) first = candidate;
  }
  return first.file;
}

Comparator<_FilenameSortEntry> _filenameComparator(
  FileSortOrder order,
  String? localeTag,
) {
  final collator = _filenameCollator(localeTag);
  return (first, second) {
    final firstNumber = first.number;
    final secondNumber = second.number;
    int result;
    if (firstNumber != null &&
        secondNumber != null &&
        first.prefix == second.prefix &&
        first.suffix == second.suffix) {
      result = firstNumber.length.compareTo(secondNumber.length);
      if (result == 0) result = firstNumber.compareTo(secondNumber);
    } else {
      result = collator.compare(first.name, second.name);
    }
    if (result != 0) return order.ascending ? result : -result;
    return _compareFileIDs(first.file, second.file);
  };
}

final _singleNumber = RegExp(r"^([^0-9]*)([0-9]+)([^0-9]*)$");
final _leadingZeros = RegExp(r"^0+");
final _asciiName = RegExp(r"^[\x00-\x7F]*$");

class _FilenameSortEntry {
  final EnteFile file;
  final String name;
  String? prefix;
  String? number;
  String? suffix;

  _FilenameSortEntry(this.file) : name = file.displayName {
    if (!_asciiName.hasMatch(name)) return;
    final match = _singleNumber.firstMatch(name);
    if (match == null) return;
    final digits = match.group(2)!;
    // Long numeric runs retain ICU's chunking rules.
    if (digits.length >= 254) return;
    prefix = match.group(1)!;
    number = digits.replaceFirst(_leadingZeros, "");
    suffix = match.group(3)!;
  }
}
