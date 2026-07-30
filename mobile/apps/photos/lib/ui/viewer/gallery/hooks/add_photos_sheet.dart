import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/l10n/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/utils/dialog_util.dart";
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

Future<dynamic> showAddPhotosSheet(
  BuildContext context,
  Collection collection,
) async {
  return await showBottomSheetComponent<dynamic>(
    context: context,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: _sheetHeightFactor,
        alignment: Alignment.bottomCenter,
        child: GalleryBoundariesProvider(
          child: AddPhotosPhotoWidget(collection),
        ),
      );
    },
    enableDrag: false,
  );
}

const double _sheetHeightFactor = 0.86;

class AddPhotosPhotoWidget extends StatelessWidget {
  final Collection collection;

  const AddPhotosPhotoWidget(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<bool> isFileSelected = ValueNotifier(false);
    final selectedFiles = SelectedFiles();
    selectedFiles.addListener(() {
      isFileSelected.value = selectedFiles.files.isNotEmpty;
    });
    final Set<int> hiddenCollectionIDs = CollectionsService.instance
        .getHiddenCollectionIds();
    // Hide the current collection files from suggestions
    hiddenCollectionIDs.add(collection.id);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.componentColors.backgroundBase,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Radii.bottomSheet),
          topRight: Radius.circular(Radii.bottomSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppBarWithBoundary(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  Spacing.xl,
                  Spacing.xl,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.addMore,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.h2.copyWith(
                          color: context.componentColors.textBase,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    IconButtonComponent(
                      tooltip: context.l10n.close,
                      variant: IconButtonComponentVariant.circular,
                      shouldSurfaceExecutionStates: false,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: IconSizes.small,
                      ),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Expanded(
              child: DelayedGallery(
                hiddenCollectionIDs: hiddenCollectionIDs,
                selectedFiles: selectedFiles,
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 428),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.xl,
                    Spacing.lg,
                    Spacing.xl,
                    Spacing.sm,
                  ),
                  child: Column(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: isFileSelected,
                        builder: (context, bool value, _) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeInOutExpo,
                            switchOutCurve: Curves.easeInOutExpo,
                            child: ButtonComponent(
                              key: ValueKey(value),
                              variant: ButtonComponentVariant.primary,
                              isDisabled: !value,
                              label: context.l10n.addSelected,
                              onTap: () async {
                                final selectedFile = selectedFiles.files;
                                final ca = CollectionActions(
                                  CollectionsService.instance,
                                );
                                await ca.addToCollection(
                                  context,
                                  collection.id,
                                  false,
                                  selectedFiles: selectedFile.toList(),
                                );
                                if (!context.mounted) return;
                                Navigator.pop(context, selectedFile);
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: Spacing.md),
                      ButtonComponent(
                        variant: ButtonComponentVariant.secondary,
                        label: context.l10n.addFromDevice,
                        onTap: () async {
                          await _onPickFromDeviceClicked(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPickFromDeviceClicked(BuildContext context) async {
    try {
      final assetPickerTextDelegate = await _getAssetPickerTextDelegate();
      if (!context.mounted) return;
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          keepScrollOffset: true,
          maxAssets: maxPickAssetLimit,
          textDelegate: assetPickerTextDelegate,
          gridCount: 6,
          pageSize: 120,
        ),
      );
      if (result != null && result.isNotEmpty) {
        final ca = CollectionActions(CollectionsService.instance);
        if (!context.mounted) return;
        await ca.addToCollection(
          context,
          collection.id,
          false,
          picketAssets: result,
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (e is StateError) {
        final PermissionState ps = await permissionService
            .requestPhotoMangerPermissions();
        if (ps != PermissionState.authorized && ps != PermissionState.limited) {
          if (!context.mounted) return;
          await showChoiceDialog(
            context,
            title: context.l10n.grantPermission,
            body: context.l10n.pleaseGrantPermissions,
            firstButtonLabel: context.l10n.ok,
            secondButtonLabel: context.l10n.cancel,
            firstButtonOnTap: () async {
              await PhotoManager.openSetting();
            },
          );
        } else {
          if (!context.mounted) return;
          await showErrorDialog(
            context,
            context.l10n.oops,
            context.l10n.somethingWentWrong + (kDebugMode ? "\n$e" : ""),
          );
        }
      }
    }
  }

  // _getAssetPickerTextDelegate returns the text delegate for the asset picker
  // This custom method is required to enforce English as the default fallback
  // instead of Chinese.
  Future<AssetPickerTextDelegate> _getAssetPickerTextDelegate() async {
    final Locale locale = (await getLocale())!;
    switch (locale.languageCode.toLowerCase()) {
      case "en":
        return const EnglishAssetPickerTextDelegate();
      case "he":
        return const HebrewAssetPickerTextDelegate();
      case "de":
        return const GermanAssetPickerTextDelegate();
      case "ru":
        return const RussianAssetPickerTextDelegate();
      case "ja":
        return const JapaneseAssetPickerTextDelegate();
      case "ar":
        return const ArabicAssetPickerTextDelegate();
      case "fr":
        return const FrenchAssetPickerTextDelegate();
      case "vi":
        return const VietnameseAssetPickerTextDelegate();
      case "tr":
        return const TurkishAssetPickerTextDelegate();
      case "ko":
        return const KoreanAssetPickerTextDelegate();
      case "zh":
        return const AssetPickerTextDelegate();
      default:
        return const EnglishAssetPickerTextDelegate();
    }
  }
}

class DelayedGallery extends StatefulWidget {
  const DelayedGallery({
    super.key,
    required this.hiddenCollectionIDs,
    required this.selectedFiles,
  });

  final Set<int> hiddenCollectionIDs;
  final SelectedFiles selectedFiles;

  @override
  State<DelayedGallery> createState() => _DelayedGalleryState();
}

class _DelayedGalleryState extends State<DelayedGallery> {
  bool _showGallery = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showGallery = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showGallery) {
      return GalleryFilesState(
        child:
            Gallery(
              inSelectionMode: true,
              asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
                return FilesDB.instance.getAllPendingOrUploadedFiles(
                  creationStartTime,
                  creationEndTime,
                  Configuration.instance.getUserID()!,
                  limit: limit,
                  asc: asc,
                  filterOptions: DBFilterOptions(
                    hideIgnoredForUpload: true,
                    dedupeUploadID: true,
                    ignoredCollectionIDs: widget.hiddenCollectionIDs,
                  ),
                  applyOwnerCheck: true,
                );
              },
              tagPrefix: "pick_add_photos_gallery",
              selectedFiles: widget.selectedFiles,
              showSelectAll: true,
              sortAsyncFn: () => false,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
            ).animate().fadeIn(
              duration: const Duration(milliseconds: 175),
              curve: Curves.easeOutCirc,
            ),
      );
    } else {
      return const EnteLoadingWidget();
    }
  }
}

class _AppBarWithBoundary extends StatefulWidget {
  final Widget child;

  const _AppBarWithBoundary({required this.child});

  @override
  State<_AppBarWithBoundary> createState() => _AppBarWithBoundaryState();
}

class _AppBarWithBoundaryState extends State<_AppBarWithBoundary>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return boundaryWidget(position: BoundaryPosition.top, child: widget.child);
  }
}
