import "dart:async";

import "package:ente_account_settings/src/active_sessions_host.dart";
import "package:ente_account_settings/src/active_sessions_settings.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_frb/active_sessions.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";

class ActiveSessionsPage extends StatefulWidget {
  const ActiveSessionsPage({super.key});

  @override
  State<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends State<ActiveSessionsPage> {
  final _logger = Logger("ActiveSessionsPage");
  List<ActiveSession>? _sessions;

  ActiveSessionsHost get _host => ActiveSessionsSettings.instance.host;

  @override
  void initState() {
    super.initState();
    _fetchActiveSessions().onError((e, s) {
      _logger.severe("failed to fetch active sessions", e, s);
      if (!mounted) return;
      unawaited(
        showErrorBottomSheetComponent<void>(
          context: context,
          title: context.strings.oops,
          message: context.strings.failedToFetchActiveSessions,
          illustration: Image.asset("assets/warning-grey.png"),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: context.strings.activeSessions,
      padding: EdgeInsets.zero,
      children: _getBodyChildren(context),
    );
  }

  List<Widget> _getBodyChildren(BuildContext context) {
    final sessions = _sessions;
    if (sessions == null) {
      return [
        SizedBox(
          height: MediaQuery.sizeOf(context).height / 2,
          child: const Center(child: LoadingComponent()),
        ),
      ];
    }

    return [
      const SizedBox(height: Spacing.xs),
      for (final session in sessions) _getSessionWidget(session),
    ];
  }

  Widget _getSessionWidget(ActiveSession session) {
    final colors = context.componentColors;
    final lastUsedAt = DateTime.fromMicrosecondsSinceEpoch(session.lastUsedAt);
    return Column(
      children: [
        InkWell(
          onTap: () => _showSessionTerminationDialog(session),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _getUAWidget(session),
                const Padding(padding: EdgeInsets.all(4)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        session.ip,
                        style: TextStyles.body.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.all(8)),
                    Flexible(
                      child: Text(
                        getFormattedTime(lastUsedAt, context: context),
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(color: colors.strokeFaint),
      ],
    );
  }

  Future<void> _terminateSession(ActiveSession session) async {
    final loading = showLoadingComponent(context, context.strings.pleaseWait);
    try {
      await _host.revokeActiveSession(session.id);
      await _fetchActiveSessions();
      await loading.hide();
    } catch (e, s) {
      await loading.hide();
      _logger.severe("failed to terminate session", e, s);
      if (!mounted) return;
      unawaited(
        showErrorBottomSheetComponent<void>(
          context: context,
          title: context.strings.oops,
          message: context.strings.somethingWentWrongPleaseTryAgain,
          illustration: Image.asset("assets/warning-grey.png"),
        ),
      );
    }
  }

  Future<void> _fetchActiveSessions() async {
    final sessions = await _host.listActiveSessions();
    sessions.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    if (mounted) {
      setState(() => _sessions = sessions);
    }
  }

  void _showSessionTerminationDialog(ActiveSession session) {
    final l10n = context.strings;
    final displayedUserAgent = session.userAgent.length > 256
        ? "${session.userAgent.substring(0, 253)}..."
        : session.userAgent;
    final message = session.isCurrent
        ? l10n.thisWillLogYouOutOfThisDevice
        : "${l10n.thisWillLogYouOutOfTheFollowingDevice}\n\n"
              "$displayedUserAgent";

    showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) {
        return BottomSheetComponent(
          title: l10n.terminateSession,
          message: message,
          illustration: Image.asset("assets/warning-grey.png"),
          actions: [
            ButtonComponent(
              label: l10n.terminate,
              variant: ButtonComponentVariant.critical,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (session.isCurrent) {
                  await _host.logoutThisDevice(context);
                } else {
                  await _terminateSession(session);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _getUAWidget(ActiveSession session) {
    final colors = context.componentColors;
    if (session.isCurrent) {
      return Text(
        context.strings.thisDevice,
        style: TextStyles.bodyBold.copyWith(color: colors.primary),
      );
    }
    return Text(
      session.prettyUserAgent,
      style: TextStyles.bodyBold.copyWith(color: colors.textBase),
    );
  }
}
