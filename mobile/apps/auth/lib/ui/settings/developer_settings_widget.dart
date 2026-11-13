import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/core/constants.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class DeveloperSettingsWidget extends StatelessWidget {
  const DeveloperSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final endpoint = Configuration.instance.getHttpEndpoint();
    if (endpoint != kDefaultProductionEndpoint) {
      final endpointURI = Uri.parse(endpoint);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          context.strings.customEndpoint(
            endpoint: "${endpointURI.host}:${endpointURI.port}",
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
