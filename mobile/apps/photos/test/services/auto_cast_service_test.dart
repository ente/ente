import "dart:async";

import "package:ente_cast/ente_cast.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/auto_cast_service.dart";

void main() {
  test("server session stop disconnects before revocation completes", () async {
    final transport = _FakeCastService();
    final gateway = _FakeCastGateway();
    final service = AutoCastService(
      transport: transport,
      gateway: gateway,
      encodePayload: (_, _, _) => "encrypted-payload",
    );
    final device = Object();
    await service.connect(device, _FakeCollection());
    final revokeCompleter = Completer<void>();
    gateway.revokeFuture = revokeCompleter.future;

    final stopFuture = service.stopServerSession("device-id");
    await Future<void>.delayed(Duration.zero);

    expect(transport.stoppedDevices, [device]);
    expect(gateway.revokedDeviceIDs, ["device-id"]);

    revokeCompleter.completeError(StateError("revoke failed"));
    await expectLater(stopFuture, throwsStateError);
  });
}

class _FakeCastService extends Fake implements CastService {
  final stoppedDevices = <Object>[];

  @override
  Future<String> connectDevice(Object device, {int? collectionID}) async {
    return "ABC123";
  }

  @override
  Future<void> stopCastingToDevice(Object device) async {
    stoppedDevices.add(device);
  }
}

class _FakeCastGateway extends Fake implements CastGateway {
  final revokedDeviceIDs = <String>[];
  Future<void>? revokeFuture;

  @override
  Future<String?> getPublicKey(String deviceCode) async {
    return "public-key";
  }

  @override
  Future<String?> publishCastPayload(
    String code,
    String castPayload,
    int collectionID,
    String castToken,
  ) async {
    return "device-id";
  }

  @override
  Future<void> revokeSessionByID(String deviceID) async {
    revokedDeviceIDs.add(deviceID);
    if (revokeFuture case final future?) {
      await future;
    }
  }
}

class _FakeCollection extends Fake implements Collection {
  @override
  int get id => 42;
}
