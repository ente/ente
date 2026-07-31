import "package:ente_cast/src/cast/multicast_lock.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("releases the multicast lock when the action fails", () async {
    const channel = MethodChannel("io.ente.cast/test-multicast");
    final events = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final result = withMulticastLock<void>(
      () async {
        events.add("action");
        throw StateError("discovery failed");
      },
      acquireLock: true,
      channel: channel,
    );

    await expectLater(result, throwsStateError);
    expect(events, ["acquire", "action", "release"]);
  });
}
