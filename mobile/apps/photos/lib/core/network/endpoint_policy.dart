import "package:photos/core/network/endpoint_origins.dart";

const kCompiledEndpoint = String.fromEnvironment(
  "endpoint",
  defaultValue: kDefaultProductionEndpoint,
);
const kLockedEndpoint = bool.fromEnvironment("lockedEndpoint");
const kConfigurableEndpoint = bool.fromEnvironment("configurableEndpoint");

enum EndpointMode { standard, locked, configurable }

enum EndpointPolicyFailureReason {
  conflictingEndpointModes,
  invalidLockedEndpoint,
  invalidConfigurableEndpoint,
  productionEndpointNotAllowed,
  existingEndpointState,
  existingAccountState,
  endpointBindingMismatch,
  endpointBindingWriteFailed,
  runtimeMutationNotAllowed,
  authenticatedOriginMismatch,
}

class EndpointPolicyException implements Exception {
  const EndpointPolicyException(this.reason, this.message);

  final EndpointPolicyFailureReason reason;
  final String message;

  String get recoveryMessage {
    return switch (reason) {
      EndpointPolicyFailureReason.conflictingEndpointModes =>
        "Rebuild the app with only one endpoint mode enabled.",
      EndpointPolicyFailureReason.invalidLockedEndpoint ||
      EndpointPolicyFailureReason.productionEndpointNotAllowed =>
        "Rebuild the app with one absolute HTTPS self-hosted endpoint.",
      EndpointPolicyFailureReason.invalidConfigurableEndpoint =>
        "Use one absolute HTTPS server origin without a path, query, fragment, or credentials.",
      EndpointPolicyFailureReason.existingEndpointState ||
      EndpointPolicyFailureReason.existingAccountState ||
      EndpointPolicyFailureReason.endpointBindingMismatch =>
        "Clear this app's data or reinstall it before trying again.",
      EndpointPolicyFailureReason.endpointBindingWriteFailed =>
        "Restart the app. If the problem continues, reinstall it.",
      EndpointPolicyFailureReason.runtimeMutationNotAllowed ||
      EndpointPolicyFailureReason.authenticatedOriginMismatch =>
        "The app blocked an unsafe server change or request.",
    };
  }

  @override
  String toString() => "EndpointPolicyException(${reason.name}): $message";
}

class EndpointPolicy {
  const EndpointPolicy({required this.mode, required this.compiledEndpoint})
    : _hasConflictingModeDefines = false;

  const EndpointPolicy.fromCompileTimeFlags({
    required bool isLocked,
    required bool isConfigurable,
    required this.compiledEndpoint,
  }) : mode = isLocked
           ? EndpointMode.locked
           : isConfigurable
           ? EndpointMode.configurable
           : EndpointMode.standard,
       _hasConflictingModeDefines = isLocked && isConfigurable;

  static const current = EndpointPolicy.fromCompileTimeFlags(
    isLocked: kLockedEndpoint,
    isConfigurable: kConfigurableEndpoint,
    compiledEndpoint: kCompiledEndpoint,
  );

  final EndpointMode mode;
  final String compiledEndpoint;
  final bool _hasConflictingModeDefines;

  bool get isLocked => mode == EndpointMode.locked;

  bool get isConfigurable => mode == EndpointMode.configurable;

  bool get hasPersistentBinding => mode != EndpointMode.standard;

  bool get enforcesAuthenticatedOrigin => hasPersistentBinding;

  String resolve({String? savedEndpoint, String? binding}) {
    validateModeConfiguration();
    return switch (mode) {
      EndpointMode.standard => normalizeLegacyEndpoint(
        savedEndpoint ?? compiledEndpoint,
      ),
      EndpointMode.locked => lockedEndpoint,
      EndpointMode.configurable =>
        binding == null
            ? configurableDefaultEndpoint
            : validateConfigurableEndpoint(binding),
    };
  }

  String get lockedEndpoint {
    validateModeConfiguration();
    return _validateAndCanonicalizeEndpoint(
      compiledEndpoint,
      allowProduction: false,
      invalidReason: EndpointPolicyFailureReason.invalidLockedEndpoint,
      policyName: "locked",
    );
  }

  String get configurableDefaultEndpoint {
    validateModeConfiguration();
    return validateConfigurableEndpoint(compiledEndpoint);
  }

  String validateConfigurableEndpoint(String endpoint) {
    return _validateAndCanonicalizeEndpoint(
      endpoint,
      allowProduction: true,
      invalidReason: EndpointPolicyFailureReason.invalidConfigurableEndpoint,
      policyName: "configurable",
    );
  }

  void validateModeConfiguration() {
    if (_hasConflictingModeDefines) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.conflictingEndpointModes,
        "lockedEndpoint and configurableEndpoint cannot both be enabled.",
      );
    }
  }

  void validateAuthenticatedRequest(Uri activeEndpoint, Uri requestUri) {
    if (!enforcesAuthenticatedOrigin) {
      return;
    }
    if (!_hasSameOrigin(activeEndpoint, requestUri)) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.authenticatedOriginMismatch,
        "An authenticated Museum request targeted a different origin.",
      );
    }
  }

  static String normalizeLegacyEndpoint(String endpoint) {
    if (endpoint == kLegacyProductionEndpoint) {
      return kDefaultProductionEndpoint;
    }
    return endpoint;
  }

  static String _validateAndCanonicalizeEndpoint(
    String endpoint, {
    required bool allowProduction,
    required EndpointPolicyFailureReason invalidReason,
    required String policyName,
  }) {
    if (endpoint.isEmpty || endpoint != endpoint.trim()) {
      throw EndpointPolicyException(
        invalidReason,
        "The $policyName endpoint is empty or contains surrounding whitespace.",
      );
    }

    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.scheme.toLowerCase() != "https" ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != "/")) {
      throw EndpointPolicyException(
        invalidReason,
        "The $policyName endpoint must be an absolute HTTPS origin without a path, query, fragment, or credentials.",
      );
    }

    final host = uri.host.toLowerCase();
    if (!allowProduction &&
        (host == Uri.parse(kDefaultProductionEndpoint).host ||
            host == Uri.parse(kLegacyProductionEndpoint).host)) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.productionEndpointNotAllowed,
        "A locked self-hosted build cannot use an Ente production API host.",
      );
    }

    return Uri(
      scheme: "https",
      host: host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static bool _hasSameOrigin(Uri expected, Uri actual) {
    return expected.scheme.toLowerCase() == actual.scheme.toLowerCase() &&
        expected.host.toLowerCase() == actual.host.toLowerCase() &&
        _effectivePort(expected) == _effectivePort(actual);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme.toLowerCase()) {
      "https" => 443,
      "http" => 80,
      _ => 0,
    };
  }
}
