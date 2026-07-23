import "package:dio/dio.dart";

/// Gateway for push notification related API endpoints.
class PushGateway {
  final Dio _enteDio;

  PushGateway(this._enteDio);

  /// Registers the push token with the server.
  ///
  /// [fcmToken] is the Firebase Cloud Messaging token.
  /// [apnsToken] is the optional Apple Push Notification service token.
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
