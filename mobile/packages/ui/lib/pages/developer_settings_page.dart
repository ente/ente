import 'package:dio/dio.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';

class DeveloperSettingsPage extends StatefulWidget {
  final String Function() getCurrentEndpoint;
  final Future<void> Function(String url) setEndpoint;

  const DeveloperSettingsPage({
    required this.getCurrentEndpoint,
    required this.setEndpoint,
    super.key,
  });

  @override
  State<DeveloperSettingsPage> createState() => _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends State<DeveloperSettingsPage> {
  final _logger = Logger('DeveloperSettingsPage');
  final _urlController = TextEditingController();
  late String _currentEndpoint;

  @override
  void initState() {
    super.initState();
    _currentEndpoint = widget.getCurrentEndpoint();
    _logger.info("Current endpoint is: $_currentEndpoint");
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.developerSettings)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: context.strings.serverEndpoint,
                hintText: _currentEndpoint,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 40),
            GradientButton(
              onTap: () async {
                final String url = _urlController.text;
                _logger.info("Entered endpoint: $url");
                try {
                  final uri = Uri.parse(url);
                  if ((uri.scheme == "http" || uri.scheme == "https")) {
                    await _ping(url);
                    await widget.setEndpoint(url);
                  } else {
                    throw const FormatException();
                  }
                } catch (e) {
                  if (!context.mounted) {
                    return;
                  }
                  // ignore: unawaited_futures
                  showErrorDialog(
                    context,
                    context.strings.invalidEndpoint,
                    context.strings.invalidEndpointMessage,
                  );
                  return;
                }
                if (context.mounted) {
                  showToast(context, context.strings.endpointUpdatedMessage);
                  Navigator.of(context).pop();
                }
              },
              text: context.strings.save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ping(String endpoint) async {
    try {
      final response = await Dio().get('$endpoint/ping');
      if (response.data['message'] != 'pong') {
        throw Exception('Invalid response');
      }
    } catch (e) {
      throw Exception('Error occurred: $e');
    }
  }
}
