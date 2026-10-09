import "package:dio/dio.dart";

class PushGateway {
  final Dio _enteDio;

  PushGateway(this._enteDio);

  Future<void> registerToken({
    required String fcmToken,
    required String platform,
    String? apnsToken,
  }) async {
    await _enteDio.post(
      "/push/token",
      data: {
        "fcmToken": fcmToken,
        "platform": platform,
        "apnsToken": apnsToken,
      },
    );
  }
}
