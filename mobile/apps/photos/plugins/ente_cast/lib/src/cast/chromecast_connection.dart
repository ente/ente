import "dart:async";

import "package:ente_cast/src/cast/chromecast_channel.dart";
import "package:ente_cast/src/cast/chromecast_device.dart";

enum ChromecastConnectionState { connecting, connected, closed }

final class ChromecastConnection {
  static const connectionNamespace = "urn:x-cast:com.google.cast.tp.connection";
  static const heartbeatNamespace = "urn:x-cast:com.google.cast.tp.heartbeat";
  static const receiverNamespace = "urn:x-cast:com.google.cast.receiver";
  static const _platformReceiverID = "receiver-0";

  final String sourceID;
  final ChromecastChannel _channel;
  final _messages = StreamController<ChromecastMessage>.broadcast();
  final _states = StreamController<ChromecastConnectionState>.broadcast();
  ChromecastConnectionState _state = ChromecastConnectionState.connecting;
  String? _applicationID;
  String? _transportID;
  bool _closing = false;

  ChromecastConnection._(this.sourceID, this._channel) {
    _channel.messages.listen(
      _handleMessage,
      onError: _messages.addError,
      onDone: _handleClosed,
      cancelOnError: false,
    );
    send(connectionNamespace, {"type": "CONNECT"});
  }

  Stream<ChromecastMessage> get messages => _messages.stream;
  Stream<ChromecastConnectionState> get states => _states.stream;
  ChromecastConnectionState get state => _state;

  static Future<ChromecastConnection> connect(
    String sourceID,
    ChromecastDevice device,
  ) async {
    final channel = await ChromecastChannel.connect(
      device.addresses,
      device.port,
    );
    return ChromecastConnection._(sourceID, channel);
  }

  void send(String namespace, Map<String, dynamic> payload) {
    _channel.send(
      namespace: namespace,
      sourceID: sourceID,
      destinationID: _transportID ?? _platformReceiverID,
      payload: payload,
    );
  }

  void sendToPlatformReceiver(String namespace, Map<String, dynamic> payload) {
    _channel.send(
      namespace: namespace,
      sourceID: sourceID,
      destinationID: _platformReceiverID,
      payload: payload,
    );
  }

  void launch(String applicationID) {
    _applicationID = applicationID;
    sendToPlatformReceiver(receiverNamespace, {
      "type": "LAUNCH",
      "appId": applicationID,
    });
  }

  Future<void> flush() => _channel.flush();

  Future<void> close() async {
    if (_closing || _state == ChromecastConnectionState.closed) {
      return;
    }
    _closing = true;
    try {
      send(connectionNamespace, {"type": "CLOSE"});
      await _channel.flush();
    } finally {
      await _channel.close();
    }
  }

  void _handleMessage(ChromecastMessage message) {
    final type = message.payload["type"];
    if (message.namespace == heartbeatNamespace && type == "PING") {
      sendToPlatformReceiver(heartbeatNamespace, {"type": "PONG"});
      return;
    }
    if (message.namespace == connectionNamespace && type == "CLOSE") {
      unawaited(close());
      return;
    }
    if (message.namespace == receiverNamespace && type == "RECEIVER_STATUS") {
      _updateTransport(message.payload);
    }
    _messages.add(message);
  }

  void _updateTransport(Map<String, dynamic> message) {
    final status = message["status"];
    final applications = status is Map ? status["applications"] : null;
    String? transportID;
    if (applications is List) {
      for (final application in applications) {
        if (application is Map &&
            application["appId"] == _applicationID &&
            application["transportId"] is String) {
          transportID = application["transportId"] as String;
          break;
        }
      }
    }

    if (transportID == null) {
      if (_transportID != null) {
        unawaited(close());
      }
      return;
    }
    if (transportID == _transportID) {
      return;
    }
    if (_transportID != null) {
      unawaited(close());
      return;
    }

    _transportID = transportID;
    send(connectionNamespace, {"type": "CONNECT"});
    if (_state != ChromecastConnectionState.connected) {
      _state = ChromecastConnectionState.connected;
      _states.add(_state);
    }
  }

  void _handleClosed() {
    if (_state == ChromecastConnectionState.closed) {
      return;
    }
    _state = ChromecastConnectionState.closed;
    _states
      ..add(_state)
      ..close();
    _messages.close();
  }
}
