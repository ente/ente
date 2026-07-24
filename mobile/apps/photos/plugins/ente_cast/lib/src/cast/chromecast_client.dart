import "dart:async";
import "dart:math";

import "package:ente_cast/src/cast/chromecast_connection.dart";
import "package:ente_cast/src/cast/chromecast_device.dart";

final class ChromecastClient {
  final _connections = <ChromecastConnection>[];
  final _random = Random.secure();

  Future<ChromecastConnection> connect(ChromecastDevice device) async {
    String sourceID;
    do {
      sourceID = "client-${_random.nextInt(1000000)}";
    } while (_connections.any((connection) => connection.sourceID == sourceID));

    final connection = await ChromecastConnection.connect(sourceID, device);
    _connections.add(connection);
    connection.states.listen((state) {
      if (state == ChromecastConnectionState.closed) {
        _connections.remove(connection);
      }
    });
    return connection;
  }

  Future<void> disconnect(ChromecastConnection connection) async {
    _connections.remove(connection);
    await connection.close();
  }
}
