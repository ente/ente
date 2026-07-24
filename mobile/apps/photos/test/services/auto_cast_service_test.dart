import "package:ente_cast/ente_cast.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/auto_cast_service.dart";

void main() {
  test(
    "stopping disconnects the device when server revocation fails",
    () async {
      final transport = _FakeCastService();
      final gateway = _FakeCastGateway();
      final service = AutoCastService(
        transport: transport,
        gateway: gateway,
        encodePayload: (_, _, _) => "encrypted-payload",
      );
      final device = Object();
      await service.connect(device, _FakeCollection());
      gateway.revokeError = StateError("revoke failed");

      await expectLater(service.stop(device), throwsStateError);

      expect(gateway.revokedDeviceIDs, ["device-id"]);
      expect(transport.stoppedDevices, [device]);
    },
  );
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
  Object? revokeError;

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
    if (revokeError case final error?) {
      throw error;
    }
  }
}

class _FakeCollection extends Fake implements Collection {
  @override
  int get id => 42;
}
