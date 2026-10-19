import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ente_crypto/src/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_sodium/flutter_sodium.dart';

Stream<Uint8List> decryptFileStream(
  Stream<List<int>> input, {
  required Uint8List header,
  required Uint8List key,
}) async* {
  final state = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(header, key);
  final buffer = Uint8List(decryptionChunkSize);
  var buffered = 0;
  var finalRecord = false;

  Uint8List pull() {
    if (finalRecord) {
      throw const FormatException('Data after final encrypted record');
    }
    if (buffered < Sodium.cryptoSecretstreamXchacha20poly1305Abytes) {
      throw const FormatException('Truncated encrypted record');
    }
    final result = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
      state,
      Uint8List.sublistView(buffer, 0, buffered),
      null,
    );
    finalRecord =
        result.tag == Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;
    buffered = 0;
    return result.m;
  }

  try {
    await for (final bytes in input) {
      var offset = 0;
      while (offset < bytes.length) {
        final count = min(buffer.length - buffered, bytes.length - offset);
        buffer.setRange(buffered, buffered + count, bytes, offset);
        buffered += count;
        offset += count;
        if (buffered == buffer.length) {
          yield pull();
        }
      }
    }
    if (buffered > 0) {
      yield pull();
    }
    if (!finalRecord) {
      throw const FormatException('Missing final encrypted record');
    }
  } finally {
    state
        .asTypedList(Sodium.cryptoSecretstreamXchacha20poly1305Statebytes)
        .fillRange(0, Sodium.cryptoSecretstreamXchacha20poly1305Statebytes, 0);
    calloc.free(state);
  }
}
