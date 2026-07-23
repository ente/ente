import "dart:io";

import "package:ente_cast/ente_cast.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/utils/dialog_util.dart";

class AutoCastDialog extends StatefulWidget {
  // async method that takes string as input
  // and returns void
  final void Function(String) onConnect;
  const AutoCastDialog(this.onConnect, {super.key});

  @override
  State<AutoCastDialog> createState() => _AutoCastDialogState();
}

class _AutoCastDialogState extends State<AutoCastDialog> {
  final Set<Object> _isDeviceTapInProgress = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = getEnteTextTheme(context);
    final AlertDialog alert = AlertDialog(
      title: Text(l10n.connectToDevice, style: textStyle.largeBold),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.autoCastDialogBody, style: textStyle.bodyMuted),
          if (Platform.isIOS)
            Text(l10n.autoCastiOSPermission, style: textStyle.bodyMuted),
          const SizedBox(height: 16),
          FutureBuilder(
            future: castService.searchDevices(),
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error.toString()}'),
                );
              } else if (!snapshot.hasData) {
                return const EnteLoadingWidget();
              }

              if (snapshot.data!.isEmpty) {
                return Center(child: Text(l10n.noDeviceFound));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: snapshot.data!.map((result) {
                  final device = result.$2;
                  final name = result.$1;
                  return GestureDetector(
                    onTap: () async {
                      if (_isDeviceTapInProgress.contains(device)) {
                        return;
                      }
                      setState(() {
                        _isDeviceTapInProgress.add(device);
                      });
                      try {
                        await _connectToYourApp(context, device);
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _isDeviceTapInProgress.remove(device);
                          });
                          if (!context.mounted) return;
                          showGenericErrorDialog(
                            context: context,
                            error: e,
                          ).ignore();
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(child: Text(name)),
                          if (_isDeviceTapInProgress.contains(device))
                            const EnteLoadingWidget(),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
    return alert;
  }

  Future<void> _connectToYourApp(
    BuildContext context,
    Object castDevice,
  ) async {
    await castService.connectDevice(
      context,
      castDevice,
      onMessage: (message) {
        if (message.containsKey(CastMessageType.pairCode)) {
          final code = message[CastMessageType.pairCode]!['code'];
          widget.onConnect(code);
        }
        if (mounted) {
          setState(() {
            _isDeviceTapInProgress.remove(castDevice);
          });
        }
      },
    );
  }
}
