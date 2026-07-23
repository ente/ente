import "package:ente_components/ente_components.dart";
import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/core/network/network.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:uuid/uuid.dart";

class _DeviceNotFoundException implements Exception {
  const _DeviceNotFoundException();
}

Future<void> _pairWithCode(
  BuildContext context,
  Collection collection,
  String code,
) async {
  final gw = CastGateway(NetworkClient.instance.enteDio);
  if (!flagService.enableMultiCast) {
    await gw.revokeAllTokens();
  }
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

Future<bool?> showPairWithCodeSheet(
  BuildContext context,
  Collection collection,
) async {
  return await showBottomSheetComponent<bool>(
    context: context,
    builder: (_) => _PairWithCodeSheet(collection: collection),
  );
}

class _PairWithCodeSheet extends StatefulWidget {
  final Collection collection;

  const _PairWithCodeSheet({required this.collection});

  @override
  State<_PairWithCodeSheet> createState() => _PairWithCodeSheetState();
}

class _PairWithCodeSheetState extends State<_PairWithCodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logger = Logger("PairWithCodeSheet");
    final textStyles = getEnteTextTheme(context);
    return BottomSheetComponent(
      title: l10n.castAlbum,
      content: Text(
        l10n.castInstruction(castUrl: flagService.castUrl),
        style: textStyles.smallMuted,
      ),
      isKeyboardAware: true,
      actions: [
        TextInputComponent(
          controller: _controller,
          maxLength: 6,
          autocorrect: false,
          autofocus: true,
          hintText: l10n.pairUsingCode,
          keyboardType: .streetAddress,
        ),
        ButtonComponent(
          label: l10n.pair,
          variant: .primary,
          onTap: () async {
            try {
              await _pairWithCode(context, widget.collection, _controller.text);
              if (mounted) {
                if (!context.mounted) return;
                await Navigator.of(context).maybePop(true);
              }
            } catch (e, s) {
              if (e is _DeviceNotFoundException) {
                if (context.mounted) {
                  showToast(context, l10n.deviceNotFound);
                }
                rethrow;
              } else if (e is CastIPMismatchException) {
                if (context.mounted) {
                  await showErrorDialog(
                    context,
                    l10n.castIPMismatchTitle,
                    l10n.castIPMismatchBody,
                  );
                }
                rethrow;
              } else {
                logger.severe('Failed to pair with code: ', e, s);
                if (context.mounted) {
                  await showGenericErrorDialog(context: context, error: e);
                }
                rethrow;
              }
            }
          },
        ),
      ],
    );
  }
}
