import "dart:async";
import "dart:io";

import "package:cast/cast.dart";
import "package:ente_cast/src/model.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";

class CastService {
  final _logger = Logger("CastService");
  final String _appId = "F5BCEC64";
  final String _pairRequestNamespace = "urn:x-cast:pair-request";

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<List<(String, Object)>> searchDevices() async {
    if (!isSupported) {
      return [];
    }

    final devices = await CastDiscoveryService().search(
      timeout: const Duration(seconds: 7),
    );
    return devices.map((device) => (device.name, device as Object)).toList();
  }

  Future<void> connectDevice(
    BuildContext context,
    Object device, {
    int? collectionID,
    void Function(Map<CastMessageType, Map<String, dynamic>>)? onMessage,
  }) async {
    if (!isSupported) {
      throw UnsupportedError("Cast is only supported on Android and iOS");
    }

    final castDevice = device as CastDevice;
    final session = await CastSessionManager().startSession(castDevice);

    session.messageStream.listen((message) {
      if (message["type"] == "RECEIVER_STATUS") {
        _logger.info("got RECEIVER_STATUS, Send request to pair");
        session.sendMessage(_pairRequestNamespace, {
          "collectionID": collectionID,
        });
      } else if (onMessage != null && message.containsKey("code")) {
        onMessage({CastMessageType.pairCode: message});
      } else if (kDebugMode) {
        _logger.info("receive message: $message");
      }
    });

    session.stateStream.listen((state) {
      if (state == CastSessionState.connected) {
        _logger.info("Send request to pair");
        session.sendMessage(_pairRequestNamespace, {});
      } else if (state == CastSessionState.closed) {
        _logger.info("Session closed");
      }
    });

    _logger.info("Send request to launch");
    session.sendMessage(CastSession.kNamespaceReceiver, {
      "type": "LAUNCH",
      "appId": _appId,
    });
  }

  Future<void> closeActiveCasts() async {
    if (!isSupported) {
      return;
    }

    final sessions = CastSessionManager().sessions;
    for (final session in sessions) {
      _logger.info("send close message for ${session.sessionId}");
      unawaited(
        Future(() {
          session.sendMessage(CastSession.kNamespaceConnection, {
            "type": "CLOSE",
          });
        }).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _logger.warning("sendMessage timed out after 5 seconds");
          },
        ),
      );
      _logger.info("close session ${session.sessionId}");
      unawaited(session.close());
    }
    CastSessionManager().sessions.clear();
  }

  Map<String, String> getActiveSessions() {
    if (!isSupported) {
      return {};
    }

    final sessions = CastSessionManager().sessions;
    final result = <String, String>{};
    for (final session in sessions) {
      if (session.state == CastSessionState.connected) {
        result[session.sessionId] = session.state.toString();
      }
    }
    return result;
  }
}
