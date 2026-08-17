import "package:dio/dio.dart";

class PushGateway {
  final Dio _enteDio;

  PushGateway(this._enteDio);

  Future<void> registerToken({
    required String fcmToken,
    String? apnsToken,
  }) async {
    await _enteDio.post(
      "/push/token",
      data: {"fcmToken": fcmToken, "apnsToken": apnsToken},
    );
  }
}
