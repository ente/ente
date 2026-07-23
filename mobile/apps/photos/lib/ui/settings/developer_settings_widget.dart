import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";

class DeveloperSettingsWidget extends StatelessWidget {
  const DeveloperSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    if (!endpointConfig.isProduction) {
      final endpoint = endpointConfig.endpoint;
      final endpointURI = Uri.parse(endpoint);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          AppLocalizations.of(
            context,
          ).customEndpoint(endpoint: "${endpointURI.host}:${endpointURI.port}"),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
