import 'dart:convert';

import 'package:ente_auth/models/code.dart';

enum WatchSharingMode { all, tags }

class WatchSharing {
  const WatchSharing({required this.mode, this.tags = const {}});

  final WatchSharingMode mode;
  final Set<String> tags;

  bool includes(Code code) => switch (mode) {
    WatchSharingMode.all => true,
    WatchSharingMode.tags => code.display.tags.any(tags.contains),
  };

  factory WatchSharing.fromJson(Map<String, dynamic> json) => WatchSharing(
    mode: WatchSharingMode.values.byName(json['mode'] as String),
    tags: (json['tags'] as List).cast<String>().toSet(),
  );

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'tags': tags.toList()..sort(),
  };
}

class WatchSelection {
  WatchSelection({
    required this.scope,
    required this.epoch,
    Map<String, WatchSharing>? watches,
  }) : watches = watches ?? {};

  final String scope;
  final String epoch;
  final Map<String, WatchSharing> watches;

  static WatchSelection? decode(String? value) {
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return WatchSelection(
        scope: json['scope'] as String,
        epoch: json['epoch'] as String,
        watches: (json['watches'] as Map<String, dynamic>).map(
          (watch, sharing) => MapEntry(
            watch,
            WatchSharing.fromJson(sharing as Map<String, dynamic>),
          ),
        ),
      );
    } on Object {
      return null;
    }
  }

  String encode() => jsonEncode({
    'scope': scope,
    'epoch': epoch,
    'watches': watches.map(
      (watch, sharing) => MapEntry(watch, sharing.toJson()),
    ),
  });
}
