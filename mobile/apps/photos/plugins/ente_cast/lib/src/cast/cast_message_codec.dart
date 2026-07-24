import "dart:convert";
import "dart:typed_data";

const maxCastFrameLength = 64 * 1024;

final class CastEnvelope {
  final String namespace;
  final String payload;

  const CastEnvelope({required this.namespace, required this.payload});
}

Uint8List encodeCastEnvelope({
  required String sourceID,
  required String destinationID,
  required String namespace,
  required String payload,
}) {
  final output = BytesBuilder(copy: false);
  _writeVarintField(output, 1, 0);
  _writeStringField(output, 2, sourceID);
  _writeStringField(output, 3, destinationID);
  _writeStringField(output, 4, namespace);
  _writeVarintField(output, 5, 0);
  _writeStringField(output, 6, payload);
  return output.takeBytes();
}

Uint8List encodeCastFrame({
  required String sourceID,
  required String destinationID,
  required String namespace,
  required String payload,
}) {
  final envelope = encodeCastEnvelope(
    sourceID: sourceID,
    destinationID: destinationID,
    namespace: namespace,
    payload: payload,
  );
  if (envelope.length > maxCastFrameLength) {
    throw const FormatException("Cast message exceeds the frame limit");
  }

  final frame = Uint8List(envelope.length + 4);
  ByteData.sublistView(frame).setUint32(0, envelope.length, Endian.big);
  frame.setRange(4, frame.length, envelope);
  return frame;
}

CastEnvelope decodeCastEnvelope(Uint8List bytes) {
  final cursor = _Cursor();
  String? namespace;
  String? payload;

  while (cursor.offset < bytes.length) {
    final tag = _readVarint(bytes, cursor);
    final field = tag >> 3;
    final wireType = tag & 7;
    if (wireType == 2) {
      final length = _readVarint(bytes, cursor);
      final end = cursor.offset + length;
      if (end > bytes.length) {
        throw const FormatException("Truncated Cast message field");
      }
      if (field == 4 || field == 6) {
        final value = utf8.decode(bytes.sublist(cursor.offset, end));
        if (field == 4) {
          namespace = value;
        } else {
          payload = value;
        }
      }
      cursor.offset = end;
    } else {
      _skipField(bytes, cursor, wireType);
    }
  }

  if (namespace == null || payload == null) {
    throw const FormatException("Incomplete Cast message");
  }
  return CastEnvelope(namespace: namespace, payload: payload);
}

final class CastFrameDecoder {
  Uint8List _pending = Uint8List(0);

  List<CastEnvelope> add(Uint8List chunk) {
    if (chunk.isNotEmpty) {
      final combined = Uint8List(_pending.length + chunk.length)
        ..setRange(0, _pending.length, _pending)
        ..setRange(_pending.length, _pending.length + chunk.length, chunk);
      _pending = combined;
    }

    final envelopes = <CastEnvelope>[];
    var consumed = 0;
    while (_pending.length - consumed >= 4) {
      final length = ByteData.sublistView(
        _pending,
        consumed,
        consumed + 4,
      ).getUint32(0, Endian.big);
      if (length == 0 || length > maxCastFrameLength) {
        throw FormatException("Invalid Cast frame length: $length");
      }
      if (_pending.length - consumed < length + 4) {
        break;
      }
      envelopes.add(
        decodeCastEnvelope(
          Uint8List.sublistView(_pending, consumed + 4, consumed + 4 + length),
        ),
      );
      consumed += length + 4;
    }

    if (consumed > 0) {
      _pending = Uint8List.fromList(_pending.sublist(consumed));
    }
    return envelopes;
  }
}

void _writeVarintField(BytesBuilder output, int field, int value) {
  _writeVarint(output, field << 3);
  _writeVarint(output, value);
}

void _writeStringField(BytesBuilder output, int field, String value) {
  final bytes = utf8.encode(value);
  _writeVarint(output, (field << 3) | 2);
  _writeVarint(output, bytes.length);
  output.add(bytes);
}

void _writeVarint(BytesBuilder output, int value) {
  var remaining = value;
  while (remaining >= 0x80) {
    output.addByte((remaining & 0x7f) | 0x80);
    remaining >>= 7;
  }
  output.addByte(remaining);
}

int _readVarint(Uint8List bytes, _Cursor cursor) {
  var value = 0;
  var shift = 0;
  while (cursor.offset < bytes.length && shift <= 63) {
    final byte = bytes[cursor.offset++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      return value;
    }
    shift += 7;
  }
  throw const FormatException("Invalid Cast message varint");
}

void _skipField(Uint8List bytes, _Cursor cursor, int wireType) {
  switch (wireType) {
    case 0:
      _readVarint(bytes, cursor);
    case 1:
      cursor.offset += 8;
    case 5:
      cursor.offset += 4;
    default:
      throw FormatException("Unsupported Cast wire type $wireType");
  }
  if (cursor.offset > bytes.length) {
    throw const FormatException("Truncated Cast message field");
  }
}

final class _Cursor {
  int offset = 0;
}
