import "dart:async";

import "package:ente_cast/src/cast/chromecast_channel.dart";
import "package:ente_cast/src/cast/chromecast_connection.dart";

const castPairRequestNamespace = "urn:x-cast:pair-request";

Future<String> waitForPairCode({
  required Stream<ChromecastMessage> messages,
  required Stream<ChromecastConnectionState> states,
  required void Function() start,
  required void Function() sendPairRequest,
  required Duration timeout,
}) async {
  final pairCode = Completer<String>();
  var pairRequestSent = false;

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!pairCode.isCompleted) {
      pairCode.completeError(error, stackTrace);
    }
  }

  void requestPairCode() {
    if (pairRequestSent || pairCode.isCompleted) {
      return;
    }
    pairRequestSent = true;
    try {
      sendPairRequest();
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
    }
  }

  final messageSubscription = messages.listen(
    (message) {
      final payload = message.payload;
      if (message.namespace == ChromecastConnection.receiverNamespace) {
        final type = payload["type"];
        if (type == "LAUNCH_ERROR" ||
            (type == "LAUNCH_STATUS" && payload["status"] == "USER_DENIED")) {
          completeError(
            CastPairingException(
              payload["reason"]?.toString() ??
                  "The Cast receiver rejected launch",
            ),
          );
          return;
        }
      }
      if (message.namespace != castPairRequestNamespace) {
        return;
      }
      final code = payload["code"];
      if (code is String && code.isNotEmpty && !pairCode.isCompleted) {
        pairCode.complete(code);
      }
    },
    onError: completeError,
    cancelOnError: false,
  );
  final stateSubscription = states.listen(
    (state) {
      switch (state) {
        case ChromecastConnectionState.connecting:
          break;
        case ChromecastConnectionState.connected:
          requestPairCode();
        case ChromecastConnectionState.closed:
          completeError(
            const CastPairingException(
              "The Cast connection closed before pairing completed",
            ),
          );
      }
    },
    onError: completeError,
    cancelOnError: false,
  );

  try {
    start();
  } catch (error, stackTrace) {
    completeError(error, stackTrace);
  }

  try {
    return await pairCode.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        "The Cast receiver did not return a pairing code",
        timeout,
      ),
    );
  } finally {
    await Future.wait([
      messageSubscription.cancel(),
      stateSubscription.cancel(),
    ]);
  }
}

final class CastPairingException implements Exception {
  final String message;

  const CastPairingException(this.message);

  @override
  String toString() => "CastPairingException: $message";
}
