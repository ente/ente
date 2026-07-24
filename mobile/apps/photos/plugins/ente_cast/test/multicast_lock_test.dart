import "package:ente_cast/src/cast/multicast_lock.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("io.ente.cast/test-multicast");
  final events = <String>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    events.clear();
  });

  test("holds the multicast lock for the action", () async {
    final result = await withMulticastLock(
      () async {
        events.add("action");
        return 42;
      },
      acquireLock: true,
      channel: channel,
    );

    expect(result, 42);
    expect(events, ["acquire", "action", "release"]);
  });

  test("releases the multicast lock when the action fails", () async {
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

  test("does not call the platform channel outside Android", () async {
    await withMulticastLock(
      () async => events.add("action"),
      acquireLock: false,
      channel: channel,
    );

    expect(events, ["action"]);
  });
}
