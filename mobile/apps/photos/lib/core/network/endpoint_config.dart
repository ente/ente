import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/events/event.dart";
import "package:shared_preferences/shared_preferences.dart";

class EndpointConfig {
  EndpointConfig(this._preferences, {this.policy = EndpointPolicy.current});

  final SharedPreferences _preferences;
  final EndpointPolicy policy;

  static const defaultEndpoint = kCompiledEndpoint;
  static const preferencesKey = "endpoint";
  static const bindingKey = "locked_endpoint_binding_v1";
  static const _accountStateKeys = {
    "email",
    "encrypted_token",
    "key_attributes",
    "token",
    "user_id",
  };

  String get endpoint {
    return policy.resolve(_preferences.getString(preferencesKey));
  }

  bool get isLocked => policy.isLocked;

  bool get isProduction {
    return endpoint == kDefaultProductionEndpoint;
  }

  Future<void> setEndpoint(String endpoint) async {
    if (isLocked) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.runtimeMutationNotAllowed,
        "Runtime endpoint changes are disabled in this locked build.",
      );
    }
    await _preferences.setString(preferencesKey, endpoint);
    Bus.instance.fire(EndpointUpdatedEvent(this.endpoint));
  }

  Future<void> validateForStartup() async {
    if (!isLocked) {
      return;
    }

    final expectedBinding = policy.lockedEndpoint;
    final currentBinding = _preferences.getString(bindingKey);
    final hasSavedEndpoint = _preferences.containsKey(preferencesKey);
    final hasAccountState = _accountStateKeys.any(_preferences.containsKey);

    if (currentBinding == null) {
      if (hasSavedEndpoint) {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.existingEndpointState,
          "This locked build found endpoint state created by another build.",
        );
      }
      if (hasAccountState) {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.existingAccountState,
          "This locked build found account state without a server binding.",
        );
      }
      await _writeBinding(expectedBinding);
      return;
    }

    if (currentBinding != expectedBinding) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.endpointBindingMismatch,
        "The stored server binding does not match this build.",
      );
    }
    if (hasSavedEndpoint) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.existingEndpointState,
        "A locked build cannot contain a runtime endpoint override.",
      );
    }
  }

  void validateAuthenticatedRequest(Uri requestUri) {
    policy.validateAuthenticatedRequest(requestUri);
  }

  Future<void> clearPreferencesForLogout() async {
    if (!isLocked) {
      await _preferences.clear();
      return;
    }

    final expectedBinding = policy.lockedEndpoint;
    if (_preferences.getString(bindingKey) != expectedBinding) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.endpointBindingMismatch,
        "The server binding changed before local account state was cleared.",
      );
    }
    for (final key in _preferences.getKeys()) {
      if (key != bindingKey) {
        await _preferences.remove(key);
      }
    }
  }

  Future<void> _writeBinding(String endpoint) async {
    final didWrite = await _preferences.setString(bindingKey, endpoint);
    if (!didWrite) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.endpointBindingWriteFailed,
        "The app could not persist its locked server binding.",
      );
    }
  }
}

Future<EndpointPolicyException?> validateEndpointStartup(
  SharedPreferences preferences, {
  EndpointPolicy policy = EndpointPolicy.current,
}) async {
  try {
    await EndpointConfig(preferences, policy: policy).validateForStartup();
    return null;
  } on EndpointPolicyException catch (e) {
    return e;
  }
}

class EndpointUpdatedEvent extends Event {
  EndpointUpdatedEvent(this.endpoint);

  final String endpoint;
}
