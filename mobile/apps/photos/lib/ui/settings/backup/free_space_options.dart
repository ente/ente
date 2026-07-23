import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/duplicate_files.dart";
import "package:photos/models/freeable_space_info.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/deduplication_service.dart";
import "package:photos/services/files_service.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/tools/debug/app_storage_viewer.dart";
import "package:photos/ui/tools/deduplicate_page.dart";
import "package:photos/ui/tools/free_space_page.dart";
import "package:photos/ui/tools/similar_images_page.dart";
import "package:photos/ui/viewer/gallery/delete_suggestions_page.dart";
import "package:photos/ui/viewer/gallery/large_files_page.dart";
import "package:photos/utils/dialog_util.dart";

class FreeUpSpaceOptionsScreen extends StatefulWidget {
  const FreeUpSpaceOptionsScreen({super.key});

  @override
  State<FreeUpSpaceOptionsScreen> createState() =>
      _FreeUpSpaceOptionsScreenState();
}

class _FreeUpSpaceOptionsScreenState extends State<FreeUpSpaceOptionsScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.freeUpSpace,
      children: [
        _buildFreeSpaceOption(
          context,
          title: l10n.freeUpDeviceSpace,
          onTap: () async => _onFreeUpDeviceSpaceTapped(),
        ),
        _description(
          l10n.freeUpDeviceSpaceDesc +
              (Platform.isIOS ? " ${l10n.freeUpDeviceSpaceDescICloud}" : ""),
        ),
        _buildFreeSpaceOption(
          context,
          title: l10n.removeDuplicates,
          onTap: () async => _onRemoveDuplicatesTapped(),
        ),
        _description(l10n.removeDuplicatesDesc),
        if (flagService.enableVectorDb) ...[
          _buildFreeSpaceOption(
            context,
            title: l10n.similarImages,
            onTap: () async {
              await routeToPage(
                context,
                const SimilarImagesPage(debugScreen: kDebugMode),
              );
            },
          ),
          _description(l10n.useMLToFindSimilarImages),
        ],
        _buildFreeSpaceOption(
          context,
          title: l10n.viewLargeFiles,
          onTap: () async {
            await routeToPage(context, LargeFilesPagePage());
          },
        ),
        _description(l10n.viewLargeFilesDesc),
        _buildFreeSpaceOption(
          context,
          title: l10n.deleteSuggestions,
          onTap: () async => _onDeleteSuggestionsTapped(),
        ),
        _description(l10n.deleteSuggestionsDesc),
        _buildFreeSpaceOption(
          context,
          title: l10n.manageDeviceStorage,
          onTap: () async {
            await routeToPage(context, const AppStorageViewer());
          },
        ),
        _description(l10n.manageDeviceStorageDesc),
      ],
    );
  }

  Widget _description(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.sm,
        bottom: Spacing.lg,
      ),
      child: Text(
        text,
        style: TextStyles.mini.copyWith(
          color: context.componentColors.textLight,
        ),
      ),
    );
  }

  MenuComponent _buildFreeSpaceOption(
    BuildContext context, {
    required String title,
    required Future<void> Function() onTap,
  }) {
    final colors = context.componentColors;
    return MenuComponent(
      title: title,
      trailing: Icon(
        Icons.chevron_right_outlined,
        color: colors.textLight,
        size: IconSizes.medium,
      ),
      showOnlyLoadingState: true,
      onTap: onTap,
    );
  }

  Future<void> _onFreeUpDeviceSpaceTapped() async {
    FreeableSpaceInfo status;
    try {
      status = await FilesService.instance.getFreeableSpaceInfo();
    } catch (e) {
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
      return;
    }

    if (status.localIDs.isEmpty) {
      if (!mounted) return;
      unawaited(
        showErrorDialog(
          context,
          AppLocalizations.of(context).allClear,
          AppLocalizations.of(context).noDeviceThatCanBeDeleted,
        ),
      );
    } else {
      if (!mounted) return;
      final bool? result = await routeToPage(context, FreeSpacePage(status));
      if (result == true) {
        _showSpaceFreedDialog(status);
      }
    }
  }

  Future<void> _onRemoveDuplicatesTapped() async {
    List<DuplicateFiles> duplicates;
    try {
      duplicates = await DeduplicationService.instance.getDuplicateFiles();
    } catch (e) {
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
      return;
    }

    if (duplicates.isEmpty) {
      if (!mounted) return;
      unawaited(
        showErrorDialog(
          context,
          AppLocalizations.of(context).noDuplicates,
          AppLocalizations.of(context).youveNoDuplicateFilesThatCanBeCleared,
        ),
      );
    } else {
      if (!mounted) return;
      final DeduplicationResult? result = await routeToPage(
        context,
        DeduplicatePage(duplicates),
      );
      if (result != null) {
        _showDuplicateFilesDeletedDialog(result);
      }
    }
  }

  Future<void> _onDeleteSuggestionsTapped() async {
    List<int> suggestionFileIDs;
    try {
      suggestionFileIDs = await CollectionsService.instance
          .fetchDeleteSuggestionFileIDs();
    } catch (e) {
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
      return;
    }

    if (suggestionFileIDs.isEmpty) {
      if (!mounted) return;
      unawaited(
        showErrorDialog(
          context,
          AppLocalizations.of(context).noDeleteSuggestion,
          AppLocalizations.of(context).youHaveNoFileSuggestedForDeletion,
        ),
      );
    } else {
      if (!mounted) return;
      await routeToPage(context, DeleteSuggestionsPage());
    }
  }

  void _showSpaceFreedDialog(FreeableSpaceInfo status) {
    if (localSettings.shouldPromptToRateUs()) {
      localSettings.setRateUsShownCount(
        localSettings.getRateUsShownCount() + 1,
      );
      showChoiceDialog(
        context,
        title: AppLocalizations.of(context).success,
        body: AppLocalizations.of(
          context,
        ).youHaveSuccessfullyFreedUp(storageSaved: formatBytes(status.size)),
        firstButtonLabel: AppLocalizations.of(context).rateUs,
        firstButtonOnTap: () async {
          await updateService.launchReviewUrl();
        },
        firstButtonType: ButtonType.primary,
        secondButtonLabel: AppLocalizations.of(context).ok,
        secondButtonOnTap: () async {
          if (Platform.isIOS) {
            showToast(
              context,
              AppLocalizations.of(context).remindToEmptyDeviceTrash,
            );
          }
        },
      );
    } else {
      showBottomSheetComponent<void>(
        context: context,
        isDismissible: true,
        builder: (_) => BottomSheetComponent(
          title: AppLocalizations.of(context).success,
          message: AppLocalizations.of(
            context,
          ).youHaveSuccessfullyFreedUp(storageSaved: formatBytes(status.size)),
          illustration: Icon(
            Icons.download_done_rounded,
            size: 64,
            color: context.componentColors.primary,
          ),
          actions: [
            ButtonComponent(
              label: AppLocalizations.of(context).ok,
              variant: ButtonComponentVariant.neutral,
              onTap: () async {
                if (Platform.isIOS) {
                  showToast(
                    context,
                    AppLocalizations.of(context).remindToEmptyDeviceTrash,
                  );
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    }
  }

  void _showDuplicateFilesDeletedDialog(DeduplicationResult result) {
    showChoiceDialog(
      context,
      title: AppLocalizations.of(context).sparkleSuccess,
      body: AppLocalizations.of(context).duplicateFileCountWithStorageSaved(
        count: result.count,
        storageSaved: formatBytes(result.size),
      ),
      firstButtonLabel: AppLocalizations.of(context).rateUs,
      firstButtonOnTap: () async {
        await updateService.launchReviewUrl();
      },
      firstButtonType: ButtonType.primary,
      secondButtonLabel: AppLocalizations.of(context).ok,
      secondButtonOnTap: () async {
        showShortToast(
          context,
          AppLocalizations.of(context).remindToEmptyEnteTrash,
        );
      },
    );
  }
}
