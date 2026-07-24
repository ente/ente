import "package:ente_cast/ente_cast.dart";
import "package:logging/logging.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/models/collection/collection.dart";
import "package:uuid/uuid.dart";

typedef CastPayloadEncoder =
    String Function(String castToken, Collection collection, String publicKey);

class AutoCastDeviceNotFoundException implements Exception {
  const AutoCastDeviceNotFoundException();
}

class AutoCastService {
  AutoCastService({
    required CastService transport,
    required CastGateway gateway,
    required CastPayloadEncoder encodePayload,
  }) : _transport = transport,
       _gateway = gateway,
       _encodePayload = encodePayload;

  final CastService _transport;
  final CastGateway _gateway;
  final CastPayloadEncoder _encodePayload;
  final _serverDeviceIDs = <Object, String>{};
  final _logger = Logger("AutoCastService");

  Future<List<(String, Object)>> searchDevices() => _transport.searchDevices();

  bool isCastingToDevice(Object device) => _transport.isCastingToDevice(device);

  Future<void> connect(Object device, Collection collection) async {
    final code = await _transport.connectDevice(
      device,
      collectionID: collection.id,
    );
    try {
      final publicKey = await _gateway.getPublicKey(code);
      if (publicKey == null) {
        throw const AutoCastDeviceNotFoundException();
      }
      final castToken = const Uuid().v4();
      final castPayload = _encodePayload(castToken, collection, publicKey);
      final deviceID = await _gateway.publishCastPayload(
        code,
        castPayload,
        collection.id,
        castToken,
      );
      if (deviceID == null) {
        _logger.warning(
          "Cast server did not return a device ID; stop cannot revoke this "
          "session remotely",
        );
      } else {
        _serverDeviceIDs[device] = deviceID;
      }
    } catch (error, stackTrace) {
      try {
        await _transport.stopCastingToDevice(device);
      } catch (stopError, stopStackTrace) {
        _logger.warning(
          "Failed to stop Cast after pairing failed",
          stopError,
          stopStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> stop(Object device) async {
    Object? stopError;
    StackTrace? stopStackTrace;
    try {
      await _transport.stopCastingToDevice(device);
    } catch (error, stackTrace) {
      stopError = error;
      stopStackTrace = stackTrace;
    }

    Object? revokeError;
    StackTrace? revokeStackTrace;
    final deviceID = _serverDeviceIDs[device];
    if (deviceID != null) {
      try {
        await _gateway.revokeSessionByID(deviceID);
        _serverDeviceIDs.remove(device);
      } catch (error, stackTrace) {
        revokeError = error;
        revokeStackTrace = stackTrace;
      }
    }

    if (stopError != null) {
      if (revokeError == null) {
        Error.throwWithStackTrace(stopError, stopStackTrace!);
      }
      _logger.warning(
        "Failed to disconnect the local Cast session",
        stopError,
        stopStackTrace,
      );
    }

    if (revokeError != null) {
      Error.throwWithStackTrace(revokeError, revokeStackTrace!);
    }
  }

  Future<void> stopServerSession(String deviceID) async {
    for (final entry in _serverDeviceIDs.entries) {
      if (entry.value == deviceID) {
        await stop(entry.key);
        return;
      }
    }
    await _gateway.revokeSessionByID(deviceID);
  }
}
