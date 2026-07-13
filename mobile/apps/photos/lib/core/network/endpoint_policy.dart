import "package:photos/core/network/endpoint_origins.dart";

const kCompiledEndpoint = String.fromEnvironment(
  "endpoint",
  defaultValue: kDefaultProductionEndpoint,
);
const kLockedEndpoint = bool.fromEnvironment("lockedEndpoint");

enum EndpointPolicyFailureReason {
  invalidLockedEndpoint,
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
      EndpointPolicyFailureReason.invalidLockedEndpoint ||
      EndpointPolicyFailureReason.productionEndpointNotAllowed =>
        "Rebuild the app with one absolute HTTPS self-hosted endpoint.",
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
  const EndpointPolicy({
    required this.isLocked,
    required this.compiledEndpoint,
  });

  static const current = EndpointPolicy(
    isLocked: kLockedEndpoint,
    compiledEndpoint: kCompiledEndpoint,
  );

  final bool isLocked;
  final String compiledEndpoint;

  String resolve(String? savedEndpoint) {
    if (isLocked) {
      return lockedEndpoint;
    }
    return normalizeLegacyEndpoint(savedEndpoint ?? compiledEndpoint);
  }

  String get lockedEndpoint {
    if (!isLocked) {
      return normalizeLegacyEndpoint(compiledEndpoint);
    }
    return _validateAndCanonicalizeLockedEndpoint(compiledEndpoint);
  }

  void validateAuthenticatedRequest(Uri requestUri) {
    if (!isLocked) {
      return;
    }
    final endpointUri = Uri.parse(lockedEndpoint);
    if (!_hasSameOrigin(endpointUri, requestUri)) {
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

  static String _validateAndCanonicalizeLockedEndpoint(String endpoint) {
    if (endpoint.isEmpty || endpoint != endpoint.trim()) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.invalidLockedEndpoint,
        "The locked endpoint is empty or contains surrounding whitespace.",
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
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.invalidLockedEndpoint,
        "The locked endpoint must be an absolute HTTPS origin without a path, query, fragment, or credentials.",
      );
    }

    final host = uri.host.toLowerCase();
    if (host == Uri.parse(kDefaultProductionEndpoint).host ||
        host == Uri.parse(kLegacyProductionEndpoint).host) {
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
