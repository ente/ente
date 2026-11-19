import 'package:collection/collection.dart';

/// Sort key for [compareNames]: lower case with Latin accents removed, so
/// "Élise" sorts with "Elise". Compute it once per item for large lists.
String nameSortKey(String name) {
  if (_isAscii(name)) return name;
  final key = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    // Combining marks, as in decomposed (NFD) file names.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final folded = _foldedLatin[rune];
    if (folded == null) {
      key.writeCharCode(rune);
    } else {
      key.write(folded);
    }
  }
  return key.toString();
}

/// Orders display names ignoring case and Latin accents, with digit runs in
/// natural order. Names that only differ in accents or case fall back to their
/// original spelling, so the order is stable.
int compareNames(String a, String b, {String? aKey, String? bKey}) {
  final result = compareAsciiLowerCaseNatural(
    aKey ?? nameSortKey(a),
    bKey ?? nameSortKey(b),
  );
  return result != 0 ? result : compareAsciiLowerCaseNatural(a, b);
}

bool _isAscii(String value) {
  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) > 0x7F) return false;
  }
  return true;
}

final Map<int, String> _foldedLatin = {
  for (final MapEntry(key: base, value: accented) in const {
    'a': 'àáâãäåāăąǎ',
    'ae': 'æ',
    'c': 'çćĉċč',
    'd': 'ďđð',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭįıǐ',
    'ij': 'ĳ',
    'j': 'ĵ',
    'k': 'ķĸ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉŋ',
    'o': 'òóôõöøōŏőǒơ',
    'oe': 'œ',
    'r': 'ŕŗř',
    's': 'śŝşšșſ',
    'ss': 'ß',
    't': 'ţťŧț',
    'th': 'þ',
    'u': 'ùúûüũūŭůűųǔư',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
  }.entries)
    for (final rune in accented.runes) rune: base,
};
