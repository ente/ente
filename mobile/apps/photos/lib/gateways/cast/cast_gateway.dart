import "package:dio/dio.dart";

class CastInfo {
  final int collectionID;
  final String deviceIP;
  final String deviceID;
  final DateTime lastUsedAt;
  final String? deviceName;

  CastInfo({
    required this.collectionID,
    required this.deviceIP,
    required this.deviceID,
    required this.lastUsedAt,
    required this.deviceName,
  });

  factory CastInfo.fromJson(dynamic json) {
    return CastInfo(
      collectionID: json["collectionID"],
      deviceIP: json["deviceIP"],
      deviceID: json["deviceID"],
      lastUsedAt: DateTime.fromMicrosecondsSinceEpoch(json["lastUsedAt"]),
      deviceName: json["deviceName"],
    );
  }
}

class CastGateway {
  final Dio _enteDio;

  CastGateway(this._enteDio);

  Future<String?> getPublicKey(String deviceCode) async {
    try {
      final response = await _enteDio.get("/cast/device-info/$deviceCode");
      return response.data["publicKey"];
    } catch (e) {
      if (e is DioException && e.response != null) {
        if (e.response!.statusCode == 404) {
          return null;
        } else if (e.response!.statusCode == 403) {
          throw CastIPMismatchException();
        } else {
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<List<CastInfo>> getAllCastSessions() async {
    final response = await _enteDio.get("/cast/device-info");
    final devices = response.data['devices'] as List<dynamic>;
    return devices.map((session) => CastInfo.fromJson(session)).toList();
  }

  Future<void> publishCastPayload(
    String code,
    String castPayload,
    int collectionID,
    String castToken,
  ) {
    return _enteDio.post(
      "/cast/cast-data",
      data: {
        "deviceCode": code,
        "encPayload": castPayload,
        "collectionID": collectionID,
        "castToken": castToken,
      },
    );
  }

  Future<void> revokeAllTokens() async {
    try {
      await _enteDio.delete("/cast/revoke-all-tokens");
    } catch (e) {
      // swallow error
    }
  }

  Future<void> revokeSession(CastInfo session) async {
    await _enteDio.delete("/cast/device-info/${session.deviceID}");
  }
}

class CastIPMismatchException implements Exception {
  CastIPMismatchException();
}
