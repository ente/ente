import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/gateways/users/models/sessions.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  Sessions? _sessions;
  final Logger _logger = Logger("SessionsPageState");

  @override
  void initState() {
    _fetchActiveSessions().onError((error, stackTrace) {
      if (!mounted) return;
      showToast(context, context.strings.failedToFetchActiveSessions);
    });
    super.initState();
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
    if (_sessions == null) {
      return [
        SizedBox(
          height: MediaQuery.sizeOf(context).height / 2,
          child: const Center(child: EnteLoadingWidget()),
        ),
      ];
    }

    return [
      const SizedBox(height: Spacing.xs),
      for (final session in _sessions!.sessions) _getSessionWidget(session),
    ];
  }

  Widget _getSessionWidget(Session session) {
    final colors = context.componentColors;
    final lastUsedTime = DateTime.fromMicrosecondsSinceEpoch(
      session.lastUsedTime,
    );
    return Column(
      children: [
        InkWell(
          onTap: () async {
            _showSessionTerminationDialog(session);
          },
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
                        getFormattedTime(lastUsedTime, context: context),
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

  Future<void> _terminateSession(Session session) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      await UserService.instance.terminateSession(session.token);
      await _fetchActiveSessions();
      await dialog.hide();
    } catch (e) {
      await dialog.hide();
      _logger.severe('failed to terminate');
      if (!mounted) return;
      // ignore: unawaited_futures
      showErrorBottomSheetComponent<void>(
        context: context,
        title: context.strings.oops,
        message: context.strings.somethingWentWrongPleaseTryAgain,
        illustration: Image.asset("assets/warning-grey.png"),
      );
    }
  }

  Future<void> _fetchActiveSessions() async {
    _sessions = await UserService.instance.getActiveSessions().onError((e, s) {
      _logger.severe("failed to fetch active sessions", e, s);
      throw e!;
    });
    if (_sessions != null) {
      _sessions!.sessions.sort((first, second) {
        return second.lastUsedTime.compareTo(first.lastUsedTime);
      });
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showSessionTerminationDialog(Session session) {
    final l10n = context.strings;
    final isLoggingOutFromThisDevice = session.isCurrentSession(
      Configuration.instance.getToken(),
    );
    final displayedUserAgent = session.ua.length > 256
        ? "${session.ua.substring(0, 253)}..."
        : session.ua;
    final message = isLoggingOutFromThisDevice
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
                if (isLoggingOutFromThisDevice) {
                  await UserService.instance.logout(context);
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

  Widget _getUAWidget(Session session) {
    final colors = context.componentColors;
    if (session.isCurrentSession(Configuration.instance.getToken())) {
      return Text(
        context.strings.thisDevice,
        style: TextStyles.bodyBold.copyWith(color: colors.primary),
      );
    }
    return Text(
      session.prettyUA,
      style: TextStyles.bodyBold.copyWith(color: colors.textBase),
    );
  }
}
