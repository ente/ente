import "dart:io";

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

Future<void> _pairWithAuto(Collection collection, String code) async {
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
  late final Future<List<(String, Object)>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = castService.searchDevices();
  }

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
          future: _devices,
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              _logger.warning(
                "Failed to discover Cast devices",
                snapshot.error,
              );
              return _statusMessage(l10n.somethingWentWrongPleaseTryAgain);
            }
            if (!snapshot.hasData) {
              return const EnteLoadingWidget(padding: 16);
            }
            if (snapshot.data!.isEmpty) {
              return _statusMessage(l10n.noDeviceFound);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: snapshot.data!.map((result) {
                final device = result.$2;
                final name = result.$1;
                final isCasting = castService.isCastingToDevice(device);
                final isInProgress = _devicesInProgress.contains(device);
                return MenuComponent(
                  title: name,
                  subtitle: isCasting ? l10n.stopCastingTitle : null,
                  isDisabled: isInProgress,
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedTvSmart),
                  trailing: isInProgress
                      ? const EnteLoadingWidget(size: 16)
                      : isCasting
                      ? IconButtonComponent(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: IconSizes.small,
                            strokeWidth: 1.6,
                          ),
                          tooltip: l10n.stopCastingTitle,
                          shouldSurfaceExecutionStates: false,
                          onTap: () async => _confirmStopCasting(device),
                        )
                      : null,
                  onTap: isCasting
                      ? null
                      : () async => _connectToDevice(device),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _statusMessage(String message) {
    final colors = context.componentColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: 14),
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
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyles.bodyBold.copyWith(color: colors.caution),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToDevice(Object device) async {
    if (_devicesInProgress.contains(device)) {
      return;
    }
    setState(() => _devicesInProgress.add(device));
    try {
      final code = await castService.connectDevice(device);
      if (!mounted) {
        await castService.stopCastingToDevice(device);
        return;
      }
      try {
        await _pairWithAuto(widget.collection, code);
      } catch (error, stackTrace) {
        try {
          await castService.stopCastingToDevice(device);
        } catch (stopError, stopStackTrace) {
          _logger.warning(
            "Failed to stop Cast after pairing failed",
            stopError,
            stopStackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (mounted) {
        await Navigator.maybePop(context);
      }
    } catch (e, s) {
      if (!mounted) return;
      await _handleError(e, s);
    } finally {
      if (mounted) {
        setState(() => _devicesInProgress.remove(device));
      }
    }
  }

  Future<void> _confirmStopCasting(Object device) async {
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.stopCastingTitle,
        message: l10n.stopCastingBody,
        illustration: Image.asset("assets/warning-grey.png"),
        actions: [
          ButtonComponent(
            label: l10n.stopCastingTitle,
            variant: ButtonComponentVariant.critical,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;
              setState(() => _devicesInProgress.add(device));
              try {
                await castService.stopCastingToDevice(device);
              } catch (e, s) {
                _logger.severe("Failed to stop casting", e, s);
                if (!mounted) return;
                await showGenericErrorDialog(context: context, error: e);
                return;
              } finally {
                if (mounted) {
                  setState(() => _devicesInProgress.remove(device));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleError(Object error, StackTrace stackTrace) async {
    final l10n = AppLocalizations.of(context);
    _logger.severe("Failed to pair automatically", error, stackTrace);
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
