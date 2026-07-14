import 'dart:io';

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/ui/notification/update/change_log_entry.dart';
import 'package:photos/ui/notification/update/change_log_strings.dart';

enum ChangeLogPageAction { openReferrals }

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
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;
    final isLocalGallery = isLocalGalleryMode;
    return BottomSheetComponent(
      title: l10n.whatsNew,
      showCloseButton: false,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actionsTopSpacing: Spacing.xxl,
      content: _getChangeLog(),
      actions: [
        ButtonComponent(
          variant: ButtonComponentVariant.primary,
          size: ButtonComponentSize.large,
          label: l10n.continueLabel,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        ButtonComponent(
          variant: ButtonComponentVariant.secondary,
          size: ButtonComponentSize.large,
          label: isLocalGallery ? l10n.rateUs : l10n.changeLogReferralCta,
          leading: Icon(Icons.favorite_rounded, color: colors.primary),
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            if (isLocalGallery) {
              await updateService.launchReviewUrl();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(ChangeLogPageAction.openReferrals);
            }
          },
        ),
      ],
    );
  }

  Widget _getChangeLog() {
    final strings = ChangeLogStrings.maybeForLocale(
      Localizations.localeOf(context),
      isLocalGallery: isLocalGalleryMode,
      isAndroid: Platform.isAndroid,
    );
    if (strings == null) {
      return const SizedBox.shrink();
    }
    final items =
        <ChangeLogEntry>[
              ChangeLogEntry(
                strings.title1,
                description: strings.desc1,
                items: [strings.desc1Item1, strings.desc1Item2]
                    .where((item) => item.trim().isNotEmpty)
                    .toList(growable: false),
                isFeature: true,
              ),
              ChangeLogEntry(
                strings.title2,
                description: strings.desc2,
                isFeature: true,
              ),
              ChangeLogEntry(
                strings.title3,
                description: strings.desc3,
                isFeature: true,
              ),
              ChangeLogEntry(
                strings.title4,
                description: strings.desc4,
                isFeature: true,
              ),
            ]
            .where(
              (entry) =>
                  entry.title.trim().isNotEmpty ||
                  (entry.description?.trim().isNotEmpty ?? false) ||
                  entry.items.isNotEmpty,
            )
            .toList(growable: false);
    return Flexible(
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 2.0,
        child: ListView.separated(
          controller: _scrollController,
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(right: Spacing.md),
          itemBuilder: (context, index) {
            return ChangeLogEntryWidget(entry: items[index]);
          },
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.lg),
          itemCount: items.length,
        ),
      ),
    );
  }
}
