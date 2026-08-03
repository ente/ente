import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/duplicate_files.dart";
import "package:photos/models/freeable_space_info.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/deduplication_service.dart";
import "package:photos/services/files_service.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/tools/debug/app_storage_viewer.dart";
import "package:photos/ui/tools/deduplicate_page.dart";
import "package:photos/ui/tools/free_space_page.dart";
import "package:photos/ui/tools/similar_images_page.dart";
import "package:photos/ui/viewer/gallery/delete_suggestions_page.dart";
import "package:photos/ui/viewer/gallery/large_files_page.dart";
import "package:photos/ui/viewer/gallery/trash_page.dart";
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
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.freeUpSpace,
      children: [
        _buildFreeSpaceOption(
          title: l10n.trash,
          subtitle: l10n.restoreOrPermanentlyDeleteItems,
          icon: HugeIcons.strokeRoundedDelete01,
          onTap: () async {
            await routeToPage(context, TrashPage());
          },
        ),
        const SizedBox(height: Spacing.sm),
        _buildFreeSpaceOption(
          title: l10n.freeUpDeviceSpace,
          subtitle:
              l10n.freeUpDeviceSpaceDesc +
              (Platform.isIOS ? " ${l10n.freeUpDeviceSpaceDescICloud}" : ""),
          icon: HugeIcons.strokeRoundedSmartPhone01,
          onTap: () async => _onFreeUpDeviceSpaceTapped(),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.review,
          style: TextStyles.display3.copyWith(
            color: context.componentColors.textBase,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        _buildReviewOptions(context, l10n),
        const SizedBox(height: Spacing.lg),
        _buildFreeSpaceOption(
          title: l10n.manageDeviceStorage,
          subtitle: l10n.manageDeviceStorageDesc,
          icon: HugeIcons.strokeRoundedDatabase,
          onTap: () async {
            await routeToPage(context, const AppStorageViewer());
          },
        ),
      ],
    );
  }

  Widget _buildReviewOptions(BuildContext context, StringsLocalizations l10n) {
    final options = <Widget>[
      if (flagService.enableVectorDb)
        _buildFreeSpaceOption(
          title: l10n.similarImages,
          subtitle: l10n.useMLToFindSimilarImages,
          icon: HugeIcons.strokeRoundedImageCrop,
          onTap: () async {
            await routeToPage(
              context,
              const SimilarImagesPage(debugScreen: kDebugMode),
            );
          },
        ),
      _buildFreeSpaceOption(
        title: l10n.removeDuplicates,
        subtitle: l10n.removeDuplicatesDesc,
        icon: HugeIcons.strokeRoundedCopy01,
        onTap: () async => _onRemoveDuplicatesTapped(),
      ),
      _buildFreeSpaceOption(
        title: l10n.viewLargeFiles,
        subtitle: l10n.viewLargeFilesDesc,
        icon: HugeIcons.strokeRoundedFile02,
        onTap: () async {
          await routeToPage(context, LargeFilesPagePage());
        },
      ),
      _buildFreeSpaceOption(
        title: l10n.deleteSuggestions,
        subtitle: l10n.deleteSuggestionsDesc,
        icon: HugeIcons.strokeRoundedDelete01,
        onTap: () async => _onDeleteSuggestionsTapped(),
      ),
    ];

    return MenuGroupComponent(items: options);
  }

  SettingsItem _buildFreeSpaceOption({
    required String title,
    required String subtitle,
    required List<List<dynamic>> icon,
    required Future<void> Function() onTap,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      showOnlyLoadingState: true,
      onTap: onTap,
      subtitleMaxLines: 2,
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
          context.strings.allClear,
          context.strings.noDeviceThatCanBeDeleted,
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
          context.strings.noDuplicates,
          context.strings.youveNoDuplicateFilesThatCanBeCleared,
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
          context.strings.noDeleteSuggestion,
          context.strings.youHaveNoFileSuggestedForDeletion,
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
        title: context.strings.success,
        body: context.strings.youHaveSuccessfullyFreedUp(
          storageSaved: formatBytes(status.size),
        ),
        firstButtonLabel: context.strings.rateUs,
        firstButtonOnTap: () async {
          await updateService.launchReviewUrl();
        },
        firstButtonType: ButtonType.primary,
        secondButtonLabel: context.strings.ok,
        secondButtonOnTap: () async {
          if (Platform.isIOS) {
            showToast(context, context.strings.remindToEmptyDeviceTrash);
          }
        },
      );
    } else {
      showBottomSheetComponent<void>(
        context: context,
        isDismissible: true,
        builder: (_) => BottomSheetComponent(
          title: context.strings.success,
          message: context.strings.youHaveSuccessfullyFreedUp(
            storageSaved: formatBytes(status.size),
          ),
          illustration: Icon(
            Icons.download_done_rounded,
            size: 64,
            color: context.componentColors.primary,
          ),
          actions: [
            ButtonComponent(
              label: context.strings.ok,
              variant: ButtonComponentVariant.neutral,
              onTap: () async {
                if (Platform.isIOS) {
                  showToast(context, context.strings.remindToEmptyDeviceTrash);
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
      title: context.strings.success,
      body: context.strings.duplicateFileCountWithStorageSaved(
        count: result.count,
        storageSaved: formatBytes(result.size),
      ),
      firstButtonLabel: context.strings.rateUs,
      firstButtonOnTap: () async {
        await updateService.launchReviewUrl();
      },
      firstButtonType: ButtonType.primary,
      secondButtonLabel: context.strings.ok,
      secondButtonOnTap: () async {
        showShortToast(context, context.strings.remindToEmptyEnteTrash);
      },
    );
  }
}
