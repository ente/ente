import "dart:typed_data";

import "package:ente_cast/src/cast/cast_message_codec.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("encodes the Cast message fields", () {
    final bytes = encodeCastEnvelope(
      sourceID: "s",
      destinationID: "d",
      namespace: "n",
      payload: "{}",
    );

    expect(
      bytes,
      Uint8List.fromList([
        8,
        0,
        18,
        1,
        115,
        26,
        1,
        100,
        34,
        1,
        110,
        40,
        0,
        50,
        2,
        123,
        125,
      ]),
    );
  });

  test("decodes length-delimited Cast fields", () {
    final encoded = encodeCastEnvelope(
      sourceID: "client-123",
      destinationID: "receiver-0",
      namespace: "urn:x-cast:pair-request",
      payload: '{"collectionID":42}',
    );

    final decoded = decodeCastEnvelope(encoded);

    expect(decoded.namespace, "urn:x-cast:pair-request");
    expect(decoded.payload, '{"collectionID":42}');
    expect(decoded.binaryPayload, isNull);
  });

  test("encodes and decodes binary Cast fields", () {
    final encoded = encodeBinaryCastEnvelope(
      sourceID: "sender-0",
      destinationID: "receiver-0",
      namespace: "urn:x-cast:com.google.cast.tp.deviceauth",
      payload: Uint8List.fromList([0, 1, 255]),
    );

    final decoded = decodeCastEnvelope(encoded);

    expect(decoded.namespace, "urn:x-cast:com.google.cast.tp.deviceauth");
    expect(decoded.payload, isNull);
    expect(decoded.binaryPayload, [0, 1, 255]);
  });

  test("rejects a truncated Cast message", () {
    expect(
      () => decodeCastEnvelope(Uint8List.fromList([34, 5, 1])),
      throwsFormatException,
    );
  });

  test("decodes fragmented and consecutive Cast frames", () {
    final first = encodeCastFrame(
      sourceID: "client-1",
      destinationID: "receiver-0",
      namespace: "first",
      payload: '{"value":1}',
    );
    final second = encodeCastFrame(
      sourceID: "client-1",
      destinationID: "receiver-0",
      namespace: "second",
      payload: '{"value":2}',
    );
    final decoder = CastFrameDecoder();

    expect(decoder.add(Uint8List.sublistView(first, 0, 3)), isEmpty);
    final decoded = decoder.add(
      Uint8List.fromList([...first.sublist(3), ...second]),
    );

    expect(decoded.map((message) => message.namespace), ["first", "second"]);
    expect(decoded.map((message) => message.payload), [
      '{"value":1}',
      '{"value":2}',
    ]);
  });

  test("rejects oversized Cast frames before buffering the payload", () {
    final header = Uint8List(4);
    ByteData.sublistView(
      header,
    ).setUint32(0, maxCastFrameLength + 1, Endian.big);

    expect(() => CastFrameDecoder().add(header), throwsFormatException);
  });
}
