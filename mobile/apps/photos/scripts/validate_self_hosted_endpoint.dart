import "dart:io";

import "package:photos/core/network/endpoint_policy.dart";

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      "Usage: dart run scripts/validate_self_hosted_endpoint.dart <endpoint>",
    );
    exitCode = 64;
    return;
  }

  try {
    final canonicalEndpoint = EndpointPolicy(
      mode: EndpointMode.locked,
      compiledEndpoint: arguments.single,
    ).lockedEndpoint;
    stdout.writeln(canonicalEndpoint);
  } on EndpointPolicyException catch (error) {
    stderr.writeln("Invalid ENTE_SELF_HOSTED_ENDPOINT: ${error.message}");
    exitCode = 64;
  }
}
