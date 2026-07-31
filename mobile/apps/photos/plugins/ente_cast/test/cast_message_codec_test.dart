import "dart:convert";
import "dart:typed_data";

import "package:ente_cast/src/cast/cast_message_codec.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("encodes text and binary Cast frames", () {
    final text = encodeCastFrame(
      sourceID: "s",
      destinationID: "d",
      namespace: "n",
      payload: "{}",
    );
    final binary = encodeBinaryCastFrame(
      sourceID: "s",
      destinationID: "d",
      namespace: "n",
      payload: Uint8List.fromList([0, 1, 255]),
    );

    expect(base64Encode(text), "AAAAEQgAEgFzGgFkIgFuKAAyAnt9");
    expect(base64Encode(binary), "AAAAEggAEgFzGgFkIgFuKAE6AwAB/w==");
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
