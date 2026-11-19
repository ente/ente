import 'package:collection/collection.dart';

String nameSortKey(String name) {
  if (_isAscii(name)) return name;
  final key = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    if (_isCombiningMark(rune)) continue;
    final folded = _foldedLatin[rune];
    if (folded == null) {
      key.writeCharCode(rune);
    } else {
      key.write(folded);
    }
  }
  return key.toString();
}

int compareNames(String a, String b, {String? aKey, String? bKey}) {
  final result = compareAsciiLowerCaseNatural(
    aKey ?? nameSortKey(a),
    bKey ?? nameSortKey(b),
  );
  return result != 0 ? result : compareAsciiLowerCaseNatural(a, b);
}

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036F;

bool _isAscii(String value) {
  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) > 0x7F) return false;
  }
  return true;
}

final Map<int, String> _foldedLatin = {
  for (final MapEntry(key: base, value: accented) in const {
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
    'ae': 'æǣǽ',
    'b': 'ḃḅḇ',
    'c': 'çćĉċčḉ',
    'd': 'ðďđḋḍḏḑḓ',
    'dz': 'ǆǳ',
    'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
    'f': 'ḟ',
    'g': 'ĝğġģǧǵḡ',
    'h': 'ĥħȟḣḥḧḩḫẖ',
    'i': 'ìíîïĩīĭįıǐȉȋḭḯỉị',
    'ij': 'ĳ',
    'j': 'ĵǰ',
    'k': 'ķĸǩḱḳḵ',
    'l': 'ĺļľŀłḷḹḻḽ',
    'lj': 'ǉ',
    'm': 'ḿṁṃ',
    'n': 'ñńņňŉŋǹṅṇṉṋ',
    'nj': 'ǌ',
    'o': 'òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
    'oe': 'œ',
    'p': 'ṕṗ',
    'r': 'ŕŗřȑȓṙṛṝṟ',
    's': 'śŝşšſșṡṣṥṧṩẛ',
    'ss': 'ß',
    't': 'ţťŧțṫṭṯṱẗ',
    'th': 'þ',
    'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
    'v': 'ṽṿ',
    'w': 'ŵẁẃẅẇẉẘ',
    'x': 'ẋẍ',
    'y': 'ýÿŷȳẏẙỳỵỷỹ',
    'z': 'źżžẑẓẕ',
  }.entries)
    for (final rune in accented.runes) rune: base,
};
