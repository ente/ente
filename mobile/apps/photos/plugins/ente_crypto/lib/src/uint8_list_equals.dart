import "dart:typed_data";

bool uint8ListEquals(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  final len = a.length;
  final aView = ByteData.sublistView(a);
  final bView = ByteData.sublistView(b);
  int i = 0;

  while (i + 7 < len) {
    final va = aView.getUint64(i, Endian.little);
    final vb = bView.getUint64(i, Endian.little);
    if (va != vb) return false;
    i += 8;
  }

  while (i < len) {
    if (a[i] != b[i]) return false;
    i++;
  }

  return true;
}
