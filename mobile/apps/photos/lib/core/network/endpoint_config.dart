import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/event.dart";
import "package:shared_preferences/shared_preferences.dart";

class EndpointConfig {
  EndpointConfig(this._preferences);

  final SharedPreferences _preferences;

  static const defaultEndpoint = String.fromEnvironment(
    "endpoint",
    defaultValue: kDefaultProductionEndpoint,
  );
  static const preferencesKey = "endpoint";

  String get endpoint {
    return _normalize(
      _preferences.getString(preferencesKey) ?? defaultEndpoint,
    );
  }

  bool get isProduction {
    return endpoint == kDefaultProductionEndpoint;
  }

  Future<void> setEndpoint(String endpoint) async {
    await _preferences.setString(preferencesKey, endpoint);
    Bus.instance.fire(EndpointUpdatedEvent(this.endpoint));
  }

  static String _normalize(String endpoint) {
    if (endpoint == kLegacyProductionEndpoint) {
      return kDefaultProductionEndpoint;
    }
    return endpoint;
  }
}

class EndpointUpdatedEvent extends Event {
  EndpointUpdatedEvent(this.endpoint);

  final String endpoint;
}
