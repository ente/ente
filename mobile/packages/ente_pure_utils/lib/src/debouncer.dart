import 'dart:async';

import 'package:flutter/material.dart';

// Call cancelDebounce when the debouncer is no longer needed.
class Debouncer {
  final Duration _duration;

  final ValueNotifier<bool> _debounceActiveNotifier = ValueNotifier(false);

  final Duration? executionInterval;
  Timer? _debounceTimer;
  final bool leading;

  Debouncer(this._duration, {this.executionInterval, this.leading = false});

  final Stopwatch _stopwatch = Stopwatch();

  void run(Future<void> Function() fn) {
    if (leading && !isActive()) {
      _stopwatch.stop();
      _stopwatch.reset();
      fn();
      _debounceTimer = Timer(_duration, () {
        _debounceActiveNotifier.value = false;
      });
      _debounceActiveNotifier.value = true;
      return;
    }

    bool shouldRunImmediately = false;
    if (executionInterval != null) {
      _stopwatch.start();
      if (_stopwatch.elapsedMilliseconds > executionInterval!.inMilliseconds) {
        shouldRunImmediately = true;
        _stopwatch.stop();
        _stopwatch.reset();
      }
    }

    if (isActive()) {
      _debounceTimer!.cancel();
    }
    _debounceTimer = Timer(
      shouldRunImmediately ? Duration.zero : _duration,
      () async {
        _stopwatch.stop();
        _stopwatch.reset();
        await fn();
        _debounceActiveNotifier.value = false;
      },
    );
    _debounceActiveNotifier.value = true;
  }

  void cancelDebounce() {
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
    }
  }

  void cancelDebounceTimer() => cancelDebounce();

  bool isActive() => _debounceTimer != null && _debounceTimer!.isActive;

  ValueNotifier<bool> get debounceActiveNotifier {
    return _debounceActiveNotifier;
  }
}
