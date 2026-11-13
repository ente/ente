import 'dart:convert';

import 'package:ente_auth/services/window_placement.dart';
import 'package:ente_logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsWindowPlacement {
  WindowsWindowPlacement(this._preferences);

  static const _channel = MethodChannel('io.ente.auth/window_geometry');
  static const _key = 'windowsWindowPlacement';
  final SharedPreferences _preferences;
  final _logger = Logger('WindowsWindowPlacement');
  Future<void> _pending = Future.value();
  bool _ready = false;
  bool _maximized = false;

  Future<bool> restore(Size fallbackSize, bool fallbackMaximized) async {
    Placement? saved;
    try {
      final json = _preferences.getString(_key);
      if (json != null) {
        saved = Placement.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    } catch (error, stack) {
      _logger.warning('Ignoring invalid window placement', error, stack);
    }
    _maximized = saved?.maximized ?? fallbackMaximized;
    try {
      final snapshot = (await _channel.invokeMapMethod<String, dynamic>(
        'snapshot',
      ))!;
      final monitors = (snapshot['monitors'] as List)
          .map((m) => Monitor.fromJson(m as Map))
          .toList();
      await _channel.invokeMethod<void>(
        'setBounds',
        rectJson(restoreBounds(saved, monitors, fallbackSize)),
      );
    } catch (error, stack) {
      _logger.warning('Could not restore window placement', error, stack);
    }
    return _maximized;
  }

  Future<void> startSaving() {
    _ready = true;
    return save();
  }

  Future<void> save({bool? maximized}) {
    if (!_ready) return Future.value();
    _pending = _pending
        .then((_) async {
          _maximized = maximized ?? _maximized;
          final snapshot = (await _channel.invokeMapMethod<String, dynamic>(
            'snapshot',
          ))!;
          if (!(snapshot['minimized'] as bool)) {
            _maximized = snapshot['maximized'] as bool;
          }
          final monitor = (snapshot['monitors'] as List)
              .map((m) => Monitor.fromJson(m as Map))
              .firstWhere((m) => m.id == snapshot['normalMonitorId']);
          final placement = captureBounds(
            readRect(snapshot['normalBounds'] as Map),
            monitor,
            _maximized,
          );
          if (!await _preferences.setString(
            _key,
            jsonEncode(placement.toJson()),
          )) {
            throw StateError('Could not persist window placement');
          }
        })
        .catchError((Object error, StackTrace stack) {
          _logger.warning('Could not save window placement', error, stack);
        });
    return _pending;
  }
}
