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
  // Keep this key stable so existing locked installations upgrade in place.
  static const bindingKey = "locked_endpoint_binding_v1";
  static const _accountStateKeys = {
    "email",
    "encrypted_token",
    "key_attributes",
    "token",
    "user_id",
  };

  String get endpoint {
    return policy.resolve(
      savedEndpoint: _preferences.getString(preferencesKey),
      binding: _preferences.getString(bindingKey),
    );
  }

  bool get isLocked => policy.isLocked;

  bool get isConfigurable => policy.isConfigurable;

  bool get enforcesAuthenticatedOrigin => policy.enforcesAuthenticatedOrigin;

  bool get hasLocalAccountState =>
      _accountStateKeys.any(_preferences.containsKey);

  bool get isProduction {
    return endpoint == kDefaultProductionEndpoint;
  }

  Future<void> setEndpoint(String endpoint) async {
    if (policy.hasPersistentBinding) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.runtimeMutationNotAllowed,
        "Direct endpoint changes are disabled in this managed build.",
      );
    }
    await _preferences.setString(preferencesKey, endpoint);
    Bus.instance.fire(EndpointUpdatedEvent(this.endpoint));
  }

  Future<bool> activateConfigurableEndpointAfterLocalLogout(
    String endpoint,
  ) async {
    policy.validateModeConfiguration();
    if (!isConfigurable) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.runtimeMutationNotAllowed,
        "Guarded endpoint activation is available only in configurable builds.",
      );
    }
    if (hasLocalAccountState) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.accountStateNotCleared,
        "Account state is still present; the server binding was not changed.",
      );
    }
    if (_preferences.containsKey(preferencesKey)) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.existingEndpointState,
        "A managed build cannot change servers while a runtime override exists.",
      );
    }

    final currentBinding = _preferences.getString(bindingKey);
    if (currentBinding == null) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.endpointBindingMismatch,
        "The active server binding is missing.",
      );
    }
    try {
      if (policy.validateConfigurableEndpoint(currentBinding) !=
          currentBinding) {
        throw const FormatException();
      }
    } on Object {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.endpointBindingMismatch,
        "The active server binding is invalid.",
      );
    }

    final canonicalEndpoint = policy.validateConfigurableEndpoint(endpoint);
    if (currentBinding == canonicalEndpoint) {
      return false;
    }

    await _writeBinding(canonicalEndpoint);
    Bus.instance.fire(EndpointUpdatedEvent(canonicalEndpoint));
    return true;
  }

  Future<void> validateForStartup() async {
    policy.validateModeConfiguration();
    if (!policy.hasPersistentBinding) {
      return;
    }

    final expectedBinding = policy.isLocked
        ? policy.lockedEndpoint
        : policy.configurableDefaultEndpoint;
    final currentBinding = _preferences.getString(bindingKey);
    final hasSavedEndpoint = _preferences.containsKey(preferencesKey);
    final hasAccountState = hasLocalAccountState;

    if (currentBinding == null) {
      if (hasSavedEndpoint) {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.existingEndpointState,
          "This managed build found endpoint state created by another build.",
        );
      }
      if (hasAccountState) {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.existingAccountState,
          "This managed build found account state without a server binding.",
        );
      }
      await _writeBinding(expectedBinding);
      return;
    }

    if (policy.isLocked) {
      if (currentBinding != expectedBinding) {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.endpointBindingMismatch,
          "The stored server binding does not match this build.",
        );
      }
    } else {
      try {
        final canonicalBinding = policy.validateConfigurableEndpoint(
          currentBinding,
        );
        if (currentBinding != canonicalBinding) {
          throw const FormatException();
        }
      } on Object {
        throw const EndpointPolicyException(
          EndpointPolicyFailureReason.endpointBindingMismatch,
          "The stored configurable server binding is invalid.",
        );
      }
    }
    if (hasSavedEndpoint) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.existingEndpointState,
        "A managed build cannot contain a runtime endpoint override.",
      );
    }
  }

  void validateAuthenticatedRequest(Uri requestUri) {
    policy.validateAuthenticatedRequest(Uri.parse(endpoint), requestUri);
  }

  Future<void> clearPreferencesForLogout() async {
    if (!policy.hasPersistentBinding) {
      await _preferences.clear();
      return;
    }

    final expectedBinding = endpoint;
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
        "The app could not persist its server binding.",
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
