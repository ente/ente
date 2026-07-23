import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_configuration/constants.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class DeveloperSettingsWidget extends StatelessWidget {
  final BaseConfiguration configuration;

  const DeveloperSettingsWidget(this.configuration, {super.key});

  @override
  Widget build(BuildContext context) {
    final endpoint = configuration.getHttpEndpoint();
    if (endpoint != kDefaultProductionEndpoint) {
      final endpointURI = Uri.parse(endpoint);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          context.strings.customEndpoint(
            "${endpointURI.host}:${endpointURI.port}",
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
