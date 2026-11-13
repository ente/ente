import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/review_service.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/notification/update/change_log_entry.dart';
import 'package:photos/ui/notification/update/change_log_strings.dart';
import 'package:url_launcher/url_launcher_string.dart';

Future<void> showChangeLogSheet(BuildContext context) async {
  await showBottomSheetComponent<void>(
    context: context,
    builder: (context) => const ChangeLogPage(),
  );
}

class ChangeLogPage extends StatefulWidget {
  const ChangeLogPage({super.key});

  @override
  State<ChangeLogPage> createState() => _ChangeLogPageState();
}

class _ChangeLogPageState extends State<ChangeLogPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    final isLocalGallery = isLocalGalleryMode;
    final continueButton = ButtonComponent(
      variant: isLocalGallery
          ? ButtonComponentVariant.primary
          : ButtonComponentVariant.secondary,
      size: ButtonComponentSize.large,
      label: l10n.continueLabel,
      shouldSurfaceExecutionStates: false,
      onTap: () async {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    return BottomSheetComponent(
      header: _ChangeLogHeader(title: l10n.whatsNew),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actionsTopSpacing: Spacing.lg,
      content: _getChangeLog(),
      actions: [
        continueButton,
        Theme(
          data: Theme.of(context).copyWith(
            extensions: [
              ComponentColorTokens(
                ComponentTheme.colorsForApp(
                  ComponentApp.locker,
                  brightness: Theme.of(context).brightness,
                ),
              ),
            ],
          ),
          child: ButtonComponent(
            variant: isLocalGallery
                ? ButtonComponentVariant.secondary
                : ButtonComponentVariant.primary,
            size: ButtonComponentSize.large,
            label: isLocalGallery ? l10n.rateUs : l10n.meetEnteLocker,
            leading: isLocalGallery
                ? Icon(Icons.favorite_rounded, color: colors.primary)
                : const EnteAppIcon(app: ComponentApp.locker),
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              if (isLocalGallery) {
                await ReviewService.launch();
              } else {
                final navigator = Navigator.of(context);
                final route = ModalRoute.of(context);
                bool launched;
                try {
                  launched = await launchUrlString(
                    'https://ente.com/locker/get',
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {
                  launched = false;
                }
                if (!context.mounted || route?.isCurrent != true) return;
                if (launched) {
                  navigator.pop();
                } else {
                  showShortToast(context, l10n.somethingWentWrong);
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _getChangeLog() {
    final colors = context.componentColors;
    final strings = ChangeLogStrings.maybeForLocale(
      Localizations.localeOf(context),
      isLocalGallery: isLocalGalleryMode,
      isAndroid: Theme.of(context).platform == TargetPlatform.android,
    );
    if (strings == null) {
      return const SizedBox.shrink();
    }
    final items = strings.entries
        .map(
          (entry) =>
              ChangeLogEntry(entry.title, description: entry.description),
        )
        .toList(growable: false);
    return Flexible(
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(
          thumbColor: WidgetStatePropertyAll(colors.fillDarkest),
          trackColor: WidgetStatePropertyAll(colors.fillDark),
          trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 5.0,
          radius: const Radius.circular(39),
          child: ListView.separated(
            controller: _scrollController,
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: Spacing.lg),
            itemBuilder: (context, index) {
              return ChangeLogEntryWidget(entry: items[index]);
            },
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.lg),
            itemCount: items.length,
          ),
        ),
      ),
    );
  }
}

class _ChangeLogHeader extends StatelessWidget {
  const _ChangeLogHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButtonComponent(
            tooltip: 'Close',
            variant: IconButtonComponentVariant.circular,
            shouldSurfaceExecutionStates: false,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: IconSizes.small,
            ),
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Image.asset(
          'assets/whats_new_illustration.png',
          width: 115,
          height: 108,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyles.display2.copyWith(color: colors.textBase),
        ),
      ],
    );
  }
}
