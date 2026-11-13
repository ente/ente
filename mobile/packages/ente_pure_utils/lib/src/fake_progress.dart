import 'dart:async';

import "package:flutter/foundation.dart";

typedef FakeProgressCallback = void Function(int count);

class FakePeriodicProgress {
  final FakeProgressCallback? callback;
  final Duration duration;
  Timer? _timer;
  bool _shouldRun = true;
  int runCount = 0;

  FakePeriodicProgress({required this.callback, required this.duration});

  void start() {
    assert(_shouldRun, "Cannot start a stopped FakePeriodicProgress");
    Future.delayed(duration, _invokePeriodically);
  }

  void stop() {
    if (_shouldRun) {
      _shouldRun = false;
      _timer?.cancel();
    }
  }

  void _invokePeriodically() {
    if (_shouldRun) {
      try {
        runCount++;
        callback?.call(runCount);
      } catch (e) {
        debugPrint("Error in FakePeriodicProgress callback: $e");
        stop();
        return;
      }
      _timer = Timer(duration, _invokePeriodically);
    }
  }
}
