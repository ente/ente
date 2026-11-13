import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

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
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: context.componentColors.backgroundBase,
        body: AppBarComponent(
          title: context.strings.developerSettings,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.xl,
                Spacing.lg,
                Spacing.xl,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            context.strings.serverEndpoint,
                            style: TextStyles.bodyBold.copyWith(
                              color: context.componentColors.textBase,
                            ),
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        MergeSemantics(
                          child: Semantics(
                            label: context.strings.serverEndpoint,
                            child: TextInputComponent(
                              controller: _urlController,
                              hintText: _currentEndpoint,
                              autofocus: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xxl),
                    ButtonComponent(
                      label: context.strings.save,
                      onTap: _saveEndpoint,
                      shouldShowSuccessState: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveEndpoint() async {
    final String url = _urlController.text;
    _logger.info("Entered endpoint: $url");
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == "http" || uri.scheme == "https") {
        await _ping(url);
        await widget.setEndpoint(url);
      } else {
        throw const FormatException();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      unawaited(
        showErrorBottomSheetComponent<void>(
          context: context,
          title: context.strings.invalidEndpoint,
          message: context.strings.invalidEndpointMessage,
        ),
      );
      return;
    }
    if (mounted) {
      final message = context.strings.endpointUpdatedMessage;
      Navigator.of(context).pop();
      showToastComponent(context, message, state: BannerComponentState.success);
    }
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
