import "dart:convert";
import "dart:typed_data";

import "package:ente_cast/src/cast/simple_protobuf.dart";

const maxCastFrameLength = 64 * 1024;

final class CastEnvelope {
  final String namespace;
  final String? payload;
  final Uint8List? binaryPayload;

  const CastEnvelope({
    required this.namespace,
    required this.payload,
    required this.binaryPayload,
  });
}

Uint8List encodeCastFrame({
  required String sourceID,
  required String destinationID,
  required String namespace,
  required String payload,
}) {
  final envelope = _encodeCastEnvelope(
    sourceID: sourceID,
    destinationID: destinationID,
    namespace: namespace,
    payloadType: 0,
    payloadField: 6,
    payload: utf8.encode(payload),
  );
  return _frame(envelope);
}

Uint8List encodeBinaryCastFrame({
  required String sourceID,
  required String destinationID,
  required String namespace,
  required Uint8List payload,
}) {
  final envelope = _encodeCastEnvelope(
    sourceID: sourceID,
    destinationID: destinationID,
    namespace: namespace,
    payloadType: 1,
    payloadField: 7,
    payload: payload,
  );
  return _frame(envelope);
}

CastEnvelope decodeCastEnvelope(Uint8List bytes) {
  String? namespace;
  int? payloadType;
  Uint8List? stringPayload;
  Uint8List? binaryPayload;
  final reader = ProtoReader(bytes);
  while (reader.hasNext) {
    final field = reader.readField();
    switch (field.number) {
      case 4:
        if (field.bytes case final value?) {
          namespace = utf8.decode(value);
        }
      case 5:
        payloadType = field.varint;
      case 6:
        stringPayload = field.bytes;
      case 7:
        binaryPayload = field.bytes;
    }
  }
  if (namespace == null || payloadType == null) {
    throw const FormatException("Incomplete Cast message");
  }
  if (payloadType == 0 && stringPayload != null) {
    return CastEnvelope(
      namespace: namespace,
      payload: utf8.decode(stringPayload),
      binaryPayload: null,
    );
  }
  if (payloadType == 1 && binaryPayload != null) {
    return CastEnvelope(
      namespace: namespace,
      payload: null,
      binaryPayload: binaryPayload,
    );
  }
  throw const FormatException("Cast payload type does not match its field");
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

Uint8List _encodeCastEnvelope({
  required String sourceID,
  required String destinationID,
  required String namespace,
  required int payloadType,
  required int payloadField,
  required List<int> payload,
}) {
  return (ProtoWriter()
        ..writeVarint(1, 0)
        ..writeString(2, sourceID)
        ..writeString(3, destinationID)
        ..writeString(4, namespace)
        ..writeVarint(5, payloadType)
        ..writeBytes(payloadField, payload))
      .takeBytes();
}

Uint8List _frame(Uint8List envelope) {
  if (envelope.length > maxCastFrameLength) {
    throw const FormatException("Cast message exceeds the frame limit");
  }
  final frame = Uint8List(envelope.length + 4);
  ByteData.sublistView(frame).setUint32(0, envelope.length, Endian.big);
  frame.setRange(4, frame.length, envelope);
  return frame;
}
