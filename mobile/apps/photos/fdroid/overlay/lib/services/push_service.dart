typedef BackgroundPushHandler = Future<void> Function(Object message);

class PushService {
  static final PushService instance = PushService._privateConstructor();

  PushService._privateConstructor();

  Future<void> init({BackgroundPushHandler? onBackgroundPush}) async {}

  static bool shouldSync(Object message) => false;
}
