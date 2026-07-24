import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:ente_cast/src/cast/cast_message_codec.dart";

final class ChromecastMessage {
  final String namespace;
  final Map<String, dynamic> payload;

  const ChromecastMessage({required this.namespace, required this.payload});
}

final class ChromecastChannel {
  final SecureSocket _socket;
  final _messages = StreamController<ChromecastMessage>.broadcast();
  final _frameDecoder = CastFrameDecoder();
  var _requestID = 0;
  Future<void>? _closeFuture;

  ChromecastChannel._(this._socket) {
    _socket.listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) {
        _messages.addError(error, stackTrace);
        unawaited(close());
      },
      onDone: _messages.close,
      cancelOnError: false,
    );
  }

  Stream<ChromecastMessage> get messages => _messages.stream;

  static Future<ChromecastChannel> connect(
    List<String> addresses,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uniqueAddresses = addresses.toSet().toList();
    if (uniqueAddresses.isEmpty) {
      throw ArgumentError.value(addresses, "addresses", "Must not be empty");
    }

    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var index = 0; index < uniqueAddresses.length; index++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }
      final addressesLeft = uniqueAddresses.length - index;
      final attemptTimeout = Duration(
        microseconds: remaining.inMicroseconds ~/ addressesLeft,
      );
      try {
        final socket = await SecureSocket.connect(
          uniqueAddresses[index],
          port,
          timeout: attemptTimeout,
          onBadCertificate: (_) => true,
        );
        return ChromecastChannel._(socket);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw TimeoutException("Timed out connecting to Cast device", timeout);
  }

  void send({
    required String namespace,
    required String sourceID,
    required String destinationID,
    required Map<String, dynamic> payload,
  }) {
    final message = Map<String, dynamic>.of(payload)
      ..putIfAbsent("requestId", () => _requestID++);
    final frame = encodeCastFrame(
      sourceID: sourceID,
      destinationID: destinationID,
      namespace: namespace,
      payload: jsonEncode(message),
    );
    _socket.add(frame);
  }

  Future<void> flush() => _socket.flush();

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await _socket.close();
  }

  void _receive(Uint8List chunk) {
    try {
      for (final envelope in _frameDecoder.add(chunk)) {
        final decoded = jsonDecode(envelope.payload);
        if (decoded is! Map) {
          throw const FormatException("Cast payload is not an object");
        }
        _messages.add(
          ChromecastMessage(
            namespace: envelope.namespace,
            payload: Map<String, dynamic>.from(decoded),
          ),
        );
      }
    } catch (error, stackTrace) {
      _messages.addError(error, stackTrace);
      unawaited(close());
    }
  }
}
