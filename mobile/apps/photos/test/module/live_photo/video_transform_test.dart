import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/module/live_photo/video_transform.dart';

void main() {
  late File clip;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('live-photo-mov-');
    clip = File('${directory.path}/clip.mov');
    addTearDown(() => directory.delete(recursive: true));
  });

  test('distinguishes a horizontal mirror from a real half-turn', () async {
    for (final version in [0, 1]) {
      for (final (x, y, mirrored) in [
        (-1, 1, true),
        (-1, -1, false),
        (1, 1, false),
      ]) {
        await clip.writeAsBytes(_movie(x, y, version: version));
        expect(await hasHorizontallyMirroredVideoTrack(clip), mirrored);
      }
    }
  });

  test('ignores nonvideo tracks and truncated files', () async {
    await clip.writeAsBytes(_movie(-1, 1, handler: 'soun'));
    expect(await hasHorizontallyMirroredVideoTrack(clip), isFalse);
    final bytes = _movie(-1, 1);
    await clip.writeAsBytes(bytes.sublist(0, bytes.length - 1));
    expect(await hasHorizontallyMirroredVideoTrack(clip), isFalse);
  });
}

List<int> _movie(int x, int y, {int version = 0, String handler = 'vide'}) {
  List<int> header(int offset, int x, int y) {
    final start = offset + version * 12;
    final data = ByteData(start + 36)
      ..setUint8(0, version)
      ..setInt32(start, x << 16)
      ..setInt32(start + 16, y << 16)
      ..setInt32(start + 32, 1 << 30);
    return data.buffer.asUint8List();
  }

  return _box('moov', [
    ..._box('mvhd', header(36, 1, 1)),
    ..._box('trak', [
      ..._box('tkhd', header(40, x, y)),
      ..._box('mdia', _box('hdlr', [...Uint8List(8), ...handler.codeUnits])),
    ]),
  ]);
}

List<int> _box(String type, List<int> payload) => [
  ...(ByteData(4)..setUint32(0, payload.length + 8)).buffer.asUint8List(),
  ...type.codeUnits,
  ...payload,
];
