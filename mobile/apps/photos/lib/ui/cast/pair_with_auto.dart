import "dart:io";

import "package:ente_cast/ente_cast.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/network/network.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:uuid/uuid.dart";

class _DeviceNotFoundException implements Exception {
  const _DeviceNotFoundException();
}

Future<void> _pairWithAuto(
  BuildContext context,
  Collection collection,
  String code,
) async {
  final gw = CastGateway(NetworkClient.instance.enteDio);
  final publicKey = await gw.getPublicKey(code);
  if (publicKey == null) {
    throw const _DeviceNotFoundException();
  }
  final castToken = const Uuid().v4();
  final castData = collectionsService.getCastData(
    castToken,
    collection,
    publicKey,
  );
  await gw.publishCastPayload(code, castData, collection.id, castToken);
}

/// Shows the auto-pairing sheet for Cast devices.
Future<void> showPairWithAutoSheet(
  BuildContext context,
  Collection collection,
) async {
  await showBottomSheetComponent<void>(
    context: context,
    builder: (_) => _PairWithAutoSheet(collection: collection),
  );
}

class _PairWithAutoSheet extends StatefulWidget {
  final Collection collection;

  const _PairWithAutoSheet({required this.collection});

  @override
  State<_PairWithAutoSheet> createState() => _PairWithAutoSheetState();
}

class _PairWithAutoSheetState extends State<_PairWithAutoSheet> {
  final _devicesInProgress = <Object>{};
  final _logger = Logger("PairWithAutoSheet");

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyles = getEnteTextTheme(context);
    final body = Platform.isIOS
        ? "${l10n.autoCastDialogBody}\n\n${l10n.autoCastiOSPermission}"
        : l10n.autoCastDialogBody;
    return BottomSheetComponent(
      isKeyboardAware: true,
      isScrollable: true,
      initialChildSize: 0.35,
      snapSizes: const [0.35, 1.0],
      snap: true,
      title: l10n.connectToDevice,
      content: Text(body, style: textStyles.smallMuted),
      actions: [
        FutureBuilder<List<(String, Object)>>(
          future: castService.searchDevices(),
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            }
            if (!snapshot.hasData) {
              return const EnteLoadingWidget(padding: 16);
            }
            if (snapshot.data!.isEmpty) {
              final colors = context.componentColors;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.fillLight,
                  borderRadius: Radii.buttonBorder,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset("assets/warning-yellow.png"),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        l10n.noDeviceFound,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyles.bodyBold.copyWith(
                          color: colors.caution,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: snapshot.data!.map((result) {
                final device = result.$2;
                final name = result.$1;
                return MenuComponent(
                  title: name,
                  isDisabled: _devicesInProgress.contains(device),
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedTvSmart),
                  onTap: () async => _connectToDevice(context, device),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _connectToDevice(BuildContext context, Object device) async {
    if (_devicesInProgress.contains(device)) {
      return;
    }
    setState(() => _devicesInProgress.add(device));
    try {
      await castService.connectDevice(
        context,
        device,
        onMessage: (message) async {
          final code = message[CastMessageType.pairCode]?["code"];
          if (code is! String) {
            return;
          }
          await _handlePairCode(context, device, code);
        },
      );
    } catch (e, s) {
      if (!context.mounted) return;
      await _handleError(context, device, e, s);
    }
  }

  Future<void> _handlePairCode(
    BuildContext context,
    Object device,
    String code,
  ) async {
    try {
      await _pairWithAuto(context, widget.collection, code);
      if (mounted) {
        if (!context.mounted) return;
        await Navigator.maybePop(context);
      }
    } catch (e, s) {
      if (!context.mounted) return;
      await _handleError(context, device, e, s);
    } finally {
      if (mounted) {
        setState(() => _devicesInProgress.remove(device));
      }
    }
  }

  Future<void> _handleError(
    BuildContext context,
    Object device,
    Object error,
    StackTrace stackTrace,
  ) async {
    final l10n = AppLocalizations.of(context);
    _logger.severe("Failed to pair automatically", error, stackTrace);
    if (mounted) {
      setState(() => _devicesInProgress.remove(device));
    }
    if (error is CastIPMismatchException) {
      await showErrorDialog(
        context,
        l10n.castIPMismatchTitle,
        l10n.castIPMismatchBody,
      );
      return;
    }
    if (error is _DeviceNotFoundException) {
      showToast(context, l10n.deviceNotFound);
      return;
    }
    await showGenericErrorDialog(context: context, error: error);
  }
}
