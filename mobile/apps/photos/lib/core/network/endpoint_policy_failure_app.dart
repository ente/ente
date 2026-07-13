import "package:flutter/material.dart";
import "package:photos/core/network/endpoint_policy.dart";

class EndpointPolicyFailureApp extends StatelessWidget {
  const EndpointPolicyFailureApp({required this.failure, super.key});

  final EndpointPolicyException failure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.gpp_bad_outlined, size: 40),
                    const SizedBox(height: 20),
                    Text(
                      "Ente Photos could not start safely",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "This self-hosted build stopped before creating a network client.",
                    ),
                    const SizedBox(height: 12),
                    Text(failure.message),
                    const SizedBox(height: 12),
                    Text(failure.recoveryMessage),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
