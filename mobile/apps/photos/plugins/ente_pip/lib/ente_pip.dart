import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

enum PipStartResult {
  started,
  // A newer `EntePip.start` call took its place.
  replaced,
  // The user closed PiP, or `EntePip.stop` was called, before it started.
  closed,
}

class PipRestore {
  final String path;
  final Duration position;

  const PipRestore(this.path, this.position);
}

// Returns true to take over playback after "back to video". The handler must
// then call `EntePip.finishRestore` once its player shows the video.
typedef PipRestoreHandler = FutureOr<bool> Function(PipRestore restore);

// Picture-in-Picture for local video files and HLS streams on iOS.
//
// The PiP player lives outside the widget tree and outlasts the screen that
// started it, so temporary video files are reference counted: screens call
// `useFile` and `deleteWhenUnused`, and a file is deleted once neither a
// screen nor PiP plays it.
class EntePip {
  EntePip._();

  static const _channel = MethodChannel("io.ente.photos/pip");
  static Future<bool>? _isSupported;
  static bool _isListening = false;

  static final _starting = <String>[];
  static var _held = <String>{};
  static final _users = <String, int>{};
  static final _waitingToDelete = <String>{};
  static final _restoreHandlers = <PipRestoreHandler>[];

  // Asked when no handler from `addRestoreHandler` takes over.
  static PipRestoreHandler? fallbackRestoreHandler;

  static Future<bool> isSupported() {
    if (!Platform.isIOS) return Future.value(false);
    return _isSupported ??= invokeIsSupported();
  }

  @visibleForTesting
  static Future<bool> invokeIsSupported() async {
    try {
      return await _channel.invokeMethod<bool>("isSupported") ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  // The most recently added handler is asked first.
  static void addRestoreHandler(PipRestoreHandler handler) {
    _listen();
    _restoreHandlers.add(handler);
  }

  static void removeRestoreHandler(PipRestoreHandler handler) {
    _restoreHandlers.remove(handler);
  }

  static Future<void> finishRestore() =>
      _channel.invokeMethod<void>("finishRestore");

  static Future<void> stop() => _channel.invokeMethod<void>("stop");

  // Plays `path` in PiP from `position`, replacing any video already in PiP.
  //
  // With `hlsPlaylist`, plays that stream and uses `path` only as its name.
  // The playlist's key must be an inline `data:` URI and its segments HTTPS
  // URLs. `path` counts as in use from this call, before any await. Throws a
  // `PlatformException` when PiP can't start.
  static Future<PipStartResult> start({
    required String path,
    required Duration position,
    required bool muted,
    required double speed,
    required bool loop,
    String? hlsPlaylist,
  }) async {
    _listen();
    _starting.add(path);
    try {
      await _channel.invokeMethod<void>("start", {
        "path": path,
        "positionMs": position.inMilliseconds,
        "muted": muted,
        "speed": speed,
        "loop": loop,
        "hlsPlaylist": ?hlsPlaylist,
      });
      return PipStartResult.started;
    } on PlatformException catch (e) {
      switch (e.code) {
        case "REPLACED":
          return PipStartResult.replaced;
        case "CLOSED":
          return PipStartResult.closed;
      }
      rethrow;
    } finally {
      _starting.remove(path);
      _deleteUnusedFiles();
    }
  }

  static void useFile(String path) {
    _users[path] = (_users[path] ?? 0) + 1;
    // The same video can be handed out at the same path again.
    _waitingToDelete.remove(path);
  }

  static void deleteWhenUnused(String path) {
    final users = (_users[path] ?? 1) - 1;
    if (users > 0) {
      _users[path] = users;
      return;
    }
    _users.remove(path);
    _waitingToDelete.add(path);
    _deleteUnusedFiles();
  }

  @visibleForTesting
  static bool isInUse(String path) =>
      _starting.contains(path) ||
      _held.contains(path) ||
      _users.containsKey(path);

  static void _listen() {
    if (_isListening) return;
    _isListening = true;
    _channel.setMethodCallHandler(handleNativeCall);
  }

  @visibleForTesting
  static Future<Object?> handleNativeCall(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map);
    switch (call.method) {
      case "held":
        _held = (args["paths"] as List).cast<String>().toSet();
        _deleteUnusedFiles();
      case "restore":
        return _restore(
          PipRestore(
            args["path"] as String,
            Duration(milliseconds: args["positionMs"] as int),
          ),
        );
    }
    return null;
  }

  static Future<bool> _restore(PipRestore restore) async {
    final handlers = [..._restoreHandlers.reversed, ?fallbackRestoreHandler];
    for (final handler in handlers) {
      try {
        if (await handler(restore)) return true;
      } catch (e, s) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: s, library: "ente_pip"),
        );
      }
    }
    return false;
  }

  static void _deleteUnusedFiles() {
    final unused = _waitingToDelete.where((path) => !isInUse(path)).toList();
    for (final path in unused) {
      _waitingToDelete.remove(path);
      final file = File(path);
      if (file.existsSync()) file.delete().ignore();
    }
  }
}
