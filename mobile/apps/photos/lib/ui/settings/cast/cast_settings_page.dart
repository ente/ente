import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/network/network.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import 'package:timeago/timeago.dart' as timeago;

class CastSettingsPage extends StatelessWidget {
  const CastSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    return SettingsPageScaffold(
      title: l10n.castSessions,
      children: [
        CastSessionsList(
          showTitle: false,
          fallback: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: max(0, MediaQuery.sizeOf(context).height * 0.5 - 200),
              ),
              Image.asset("assets/empty_casts.png"),
              const SizedBox(height: 16),
              Text(l10n.noSessionsFound, style: textTheme.h4Bold),
            ],
          ),
        ),
      ],
    );
  }
}

/// Displays active cast sessions or the provided fallback when empty.
class CastSessionsList extends StatefulWidget {
  /// Creates a cast sessions list.
  const CastSessionsList({
    required this.showTitle,
    required this.fallback,
    this.initialSessions,
    super.key,
  });

  /// Whether to display the active sessions title.
  final bool showTitle;

  /// Widget shown when there are no cast sessions.
  final Widget fallback;

  final List<CastInfo>? initialSessions;

  @override
  State<CastSessionsList> createState() => _CastSessionsListState();
}

class _CastSessionsListState extends State<CastSessionsList> {
  late Future<List<CastInfo>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    final gw = CastGateway(NetworkClient.instance.enteDio);
    _sessionsFuture = widget.initialSessions == null
        ? gw.getAllCastSessions()
        : Future.value(widget.initialSessions!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;
    final logger = Logger("CastSessionsList");
    return FutureBuilder(
      future: _sessionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: EnteLoadingWidget());
        }
        if (snapshot.hasError) {
          throw snapshot.error!;
        }
        if (!snapshot.hasData || snapshot.data == null) {
          logger.severe("No data returned by get all cast sessions.");
          showGenericErrorDialog(context: context, error: null);
          return const Column(children: []);
        }
        if (snapshot.data!.isEmpty) {
          return widget.fallback;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle) ...[
              const SizedBox(height: Spacing.xxl),
              Text(
                l10n.activeSessions,
                style: TextStyles.h2.copyWith(color: colors.textBase),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            for (final session in snapshot.data!) ...[
              _CastSessionItem(
                session: session,
                onRevokeSession: (session) => _revokeSession(session, logger),
              ),
              const SizedBox(height: Spacing.sm),
            ],
          ],
        );
      },
    );
  }

  Future<void> _revokeSession(CastInfo session, Logger logger) async {
    final l10n = AppLocalizations.of(context);
    final gw = CastGateway(NetworkClient.instance.enteDio);
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
              try {
                await gw.revokeSession(session);
              } catch (e, s) {
                logger.severe('Failed to revoke cast session: ', e, s);
                if (!mounted) return;
                await showGenericErrorDialog(context: context, error: e);
                return;
              }
              _refresh();
            },
          ),
        ],
      ),
    );
  }

  void _refresh() {
    final gw = CastGateway(NetworkClient.instance.enteDio);
    setState(() {
      _sessionsFuture = gw.getAllCastSessions();
    });
  }
}

class _CastSessionItem extends StatelessWidget {
  const _CastSessionItem({
    required this.session,
    required this.onRevokeSession,
  });

  final CastInfo session;
  final Future<void> Function(CastInfo session) onRevokeSession;

  @override
  Widget build(BuildContext context) {
    final collection = CollectionsService.instance.getCollectionByID(
      session.collectionID,
    );
    final title = collection?.displayName ?? session.collectionID.toString();
    return SettingsItem(
      title: "$title on ${session.deviceName ?? session.deviceIP}",
      subtitle: timeago.format(session.lastUsedAt),
      icon: HugeIcons.strokeRoundedTvSmart,
      showChevron: false,
      showOnlyLoadingState: true,
      shouldSurfaceExecutionStates: false,
      trailing: IconButtonComponent(
        icon: const HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          size: IconSizes.small,
          strokeWidth: 1.6,
        ),
        onTap: () async {
          await onRevokeSession(session);
        },
        shouldSurfaceExecutionStates: false,
        shouldShowSuccessConfirmation: false,
      ),
    );
  }
}
