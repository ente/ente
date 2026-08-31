import "dart:async";

import "package:ente_events/event_bus.dart";
import "package:ente_events/models/signed_in_event.dart";
import "package:ente_events/models/signed_out_event.dart";
import "package:ente_feature_flag/ente_feature_flag.dart";
import "package:ente_network/network.dart";
import "package:shared_preferences/shared_preferences.dart";

class FeatureFlagService {
  FeatureFlagService._privateConstructor();

  static final instance = FeatureFlagService._privateConstructor();

  late SharedPreferences _preferences;
  late FlagService _flagService;

  bool get internalUser => _flagService.internalUser;
  bool get documentScanner => internalUser;

  void init(SharedPreferences preferences) {
    _preferences = preferences;
    _reset();
    Bus.instance.on<SignedInEvent>().listen((_) {
      unawaited(refreshInternalUser());
    });
    Bus.instance.on<SignedOutEvent>().listen((_) {
      _reset();
    });
  }

  Future<bool> refreshInternalUser() async {
    await _flagService.tryRefreshFlags();
    return internalUser;
  }

  void _reset() {
    _flagService = FlagService(_preferences, Network.instance.enteDio);
  }
}
