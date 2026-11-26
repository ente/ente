import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:random_access_source/random_access_source.dart';

typedef _Box = ({int start, int end});

// Remove this matrix check and the viewer flips once the bundled player
// honors MOV track mirroring on both Android and iOS.
Future<bool> hasHorizontallyMirroredVideoTrack(File clip) async {
  try {
    final file = ReadAheadRASource(await FileRASource.loadFile(clip));
    try {
      return await file.hasHorizontalMirror();
    } finally {
      await file.close();
    }
  } on Exception {
    return false;
  }
}

extension on RandomAccessSource {
  Future<bool> hasHorizontalMirror() async {
    final root = (start: 0, end: await length());
    final movie = await _child(root, 'moov');
    if (movie == null ||
        !await _hasMatrix(await _child(movie, 'mvhd'), 36, 1)) {
      return false;
    }

    bool? mirrored;
    await for (final track in _children(movie, 'trak')) {
      final media = await _child(track, 'mdia');
      final handler = await _child(media, 'hdlr');
      if (handler == null || handler.end - handler.start < 12) continue;
      await seek(handler.start + 8);
      if (String.fromCharCodes(await mustRead(4)) != 'vide') continue;
      if (mirrored != null) return false;
      mirrored = await _hasMatrix(await _child(track, 'tkhd'), 40, -1);
    }
    return mirrored ?? false;
  }

  Future<_Box?> _child(_Box? parent, String type) async {
    if (parent == null) return null;
    await for (final box in _children(parent, type)) {
      return box;
    }
    return null;
  }

  Stream<_Box> _children(_Box parent, String type) async* {
    var offset = parent.start;
    for (var count = 0; offset < parent.end; count++) {
      final remaining = parent.end - offset;
      if (count == 256 || remaining < 8) {
        throw const FormatException('Incomplete MOV box list');
      }
      await seek(offset);
      final bytes = await mustRead(min(remaining, 16));
      final header = ByteData.sublistView(bytes);
      final declared = header.getUint32(0);
      final headerSize = declared == 1 ? 16 : 8;
      if (remaining < headerSize) {
        throw const FormatException('Short MOV header');
      }
      final size = switch (declared) {
        0 => remaining,
        1 => header.getUint64(8),
        _ => declared,
      };
      if (size < headerSize || size > remaining) {
        throw const FormatException('Invalid MOV box size');
      }
      if (String.fromCharCodes(bytes, 4, 8) == type) {
        yield (start: offset + headerSize, end: offset + size);
      }
      offset += size;
    }
  }

  Future<bool> _hasMatrix(_Box? box, int offset, int xScale) async {
    if (box == null || box.end == box.start) return false;
    await seek(box.start);
    final version = await readByte();
    if (version != 0 && version != 1) return false;
    final matrixStart = box.start + offset + version * 12;
    if (box.end - matrixStart < 36) return false;
    await seek(matrixStart);
    final matrix = ByteData.sublistView(await mustRead(36));
    return matrix.getInt32(0) == xScale * (1 << 16) &&
        matrix.getInt32(4) == 0 &&
        matrix.getInt32(8) == 0 &&
        matrix.getInt32(12) == 0 &&
        matrix.getInt32(16) == 1 << 16 &&
        matrix.getInt32(20) == 0 &&
        matrix.getInt32(32) == 1 << 30;
  }
}
