import "dart:async";

import "package:ente_cast/src/cast/cast_pairing.dart";
import "package:ente_cast/src/cast/chromecast_channel.dart";
import "package:ente_cast/src/cast/chromecast_connection.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("requests and returns the receiver pairing code", () async {
    final messages = StreamController<ChromecastMessage>.broadcast(sync: true);
    final states = StreamController<ChromecastConnectionState>.broadcast(
      sync: true,
    );
    var pairRequests = 0;
    final result = waitForPairCode(
      messages: messages.stream,
      states: states.stream,
      initialState: ChromecastConnectionState.connecting,
      start: () {},
      sendPairRequest: () => pairRequests++,
      timeout: const Duration(seconds: 1),
    );

    states.add(ChromecastConnectionState.connected);
    messages.add(
      const ChromecastMessage(
        namespace: castPairRequestNamespace,
        payload: {"code": "123456"},
      ),
    );

    expect(await result, "123456");
    expect(pairRequests, 1);
    await messages.close();
    await states.close();
  });

  test("surfaces receiver launch failures", () async {
    final messages = StreamController<ChromecastMessage>.broadcast(sync: true);
    final states = StreamController<ChromecastConnectionState>.broadcast(
      sync: true,
    );
    final result = waitForPairCode(
      messages: messages.stream,
      states: states.stream,
      initialState: ChromecastConnectionState.connecting,
      start: () => messages.add(
        const ChromecastMessage(
          namespace: ChromecastConnection.receiverNamespace,
          payload: {"type": "LAUNCH_ERROR", "reason": "NOT_FOUND"},
        ),
      ),
      sendPairRequest: () {},
      timeout: const Duration(seconds: 1),
    );

    await expectLater(result, throwsA(isA<CastPairingException>()));
    await messages.close();
    await states.close();
  });

  test("surfaces a connection that closes before pairing", () async {
    final messages = StreamController<ChromecastMessage>.broadcast(sync: true);
    final states = StreamController<ChromecastConnectionState>.broadcast(
      sync: true,
    );
    final result = waitForPairCode(
      messages: messages.stream,
      states: states.stream,
      initialState: ChromecastConnectionState.connecting,
      start: () => states.add(ChromecastConnectionState.closed),
      sendPairRequest: () {},
      timeout: const Duration(seconds: 1),
    );

    await expectLater(result, throwsA(isA<CastPairingException>()));
    await messages.close();
    await states.close();
  });

  test("times out when the receiver never returns a code", () async {
    final messages = StreamController<ChromecastMessage>.broadcast(sync: true);
    final states = StreamController<ChromecastConnectionState>.broadcast(
      sync: true,
    );
    final result = waitForPairCode(
      messages: messages.stream,
      states: states.stream,
      initialState: ChromecastConnectionState.connecting,
      start: () {},
      sendPairRequest: () {},
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(result, throwsA(isA<TimeoutException>()));
    await messages.close();
    await states.close();
  });
}
