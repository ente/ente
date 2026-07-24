import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

const _multicastChannel = MethodChannel("io.ente.cast/multicast");

Future<T> withMulticastLock<T>(
  Future<T> Function() action, {
  bool? acquireLock,
  MethodChannel channel = _multicastChannel,
}) async {
  final shouldAcquire = acquireLock ?? (!kIsWeb && Platform.isAndroid);
  if (!shouldAcquire) {
    return action();
  }

  await channel.invokeMethod<void>("acquire");
  try {
    return await action();
  } finally {
    await channel.invokeMethod<void>("release");
  }
}
