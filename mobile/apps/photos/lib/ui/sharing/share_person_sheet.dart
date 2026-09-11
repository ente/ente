import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/ml/face/person.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/service_locator.dart' as services;
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/share_util.dart';

const maxPersonRawShareFiles = 50;

Future<void> showSharePersonSheet(
  BuildContext context, {
  required List<EnteFile> files,
  required GlobalKey shareButtonKey,
  PersonEntity? person,
}) async {
  final album = await showBottomSheetComponent<Collection>(
    context: context,
    builder: (_) => _SharePersonSheet(person: person, files: files),
  );
  if (album == null || !context.mounted) return;
  await shareAlbumLink(
    context,
    CollectionsService.instance.getPublicUrl(album),
    shareButtonKey,
    albumName: album.displayName,
    albumDescription: album.displayDescription,
  );
}

class _SharePersonSheet extends StatefulWidget {
  const _SharePersonSheet({required this.person, required this.files});

  final PersonEntity? person;
  final List<EnteFile> files;

  @override
  State<_SharePersonSheet> createState() => _SharePersonSheetState();
}

class _SharePersonSheetState extends State<_SharePersonSheet> {
  final _logger = Logger('_SharePersonSheetState');
  final _rawShareButtonKey = GlobalKey();
  final _selectedFiles = SelectedFiles();
  late Set<EnteFile> _selectionBeforeAutoAdd;
  bool _autoAdd = false;

  List<EnteFile> get _filesToShare =>
      widget.files.where(_selectedFiles.isFileSelected).toList();
  bool get _canShareFiles =>
      !_autoAdd &&
      _selectedFiles.files.isNotEmpty &&
      _selectedFiles.files.length <= maxPersonRawShareFiles;

  @override
  void initState() {
    super.initState();
    _selectedFiles.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  void _setAutoAdd(bool value) {
    _autoAdd = value;
    if (value) {
      _selectionBeforeAutoAdd = Set.of(_selectedFiles.files);
      _selectedFiles.replaceSelection(widget.files.toSet());
    } else {
      _selectedFiles.replaceSelection(_selectionBeforeAutoAdd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.componentColors;
    final person = widget.person;
    return FractionallySizedBox(
      heightFactor: 0.86,
      alignment: Alignment.bottomCenter,
      child: GalleryBoundariesProvider(
        child: BottomSheetComponent(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
          header: _SharePersonSheetBoundary(
            position: BoundaryPosition.top,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      person == null
                          ? strings.sharePhotos
                          : strings.sharePersonPhotos(name: person.data.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.h2.copyWith(color: colors.textBase),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  IconButtonComponent(
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
                    variant: IconButtonComponentVariant.circular,
                    tooltip: strings.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          showCloseButton: false,
          content: Expanded(child: _buildContent(context)),
          actions: [
            _SharePersonSheetBoundary(
              position: BoundaryPosition.bottom,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ButtonComponent(
                      label: strings.shareLink,
                      density: ButtonComponentDensity.compact,
                      isDisabled: _selectedFiles.files.isEmpty,
                      shouldSurfaceExecutionStates: false,
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLink02,
                        size: IconSizes.small,
                      ),
                      onTap: _shareLink,
                    ),
                    AnimatedCrossFade(
                      duration: Motion.standard,
                      firstCurve: Curves.easeInOut,
                      secondCurve: Curves.easeInOut,
                      sizeCurve: Curves.easeInOut,
                      crossFadeState: _canShareFiles
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Padding(
                        padding: const EdgeInsets.only(top: Spacing.md),
                        child: ButtonComponent(
                          key: _rawShareButtonKey,
                          label: strings.shareItemCount(
                            count: _selectedFiles.files.length,
                          ),
                          density: ButtonComponentDensity.compact,
                          variant: ButtonComponentVariant.secondary,
                          shouldSurfaceExecutionStates: false,
                          onTap: _shareFiles,
                        ),
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final strings = context.strings;
    final person = widget.person;
    final selection = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Column(
        children: [
          _selectionRow(context),
          const SizedBox(height: Spacing.lg),
        ],
      ),
    );
    return Column(
      children: [
        if (person == null)
          selection
        else ...[
          AnimatedCrossFade(
            duration: Motion.standard,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            sizeCurve: Curves.easeInOut,
            crossFadeState: _autoAdd
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: selection,
            secondChild: const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
            child: MenuComponent(
              title: strings.shareAllPersonPhotos,
              subtitle: strings.shareAllPersonPhotosDescription(
                name: person.data.name,
              ),
              trailing: ToggleSwitchComponent(
                selected: _autoAdd,
                onChanged: _setAutoAdd,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
        ],
        Expanded(child: _buildGallery()),
      ],
    );
  }

  Widget _selectionRow(BuildContext context) {
    final strings = context.strings;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SelectionSummaryChipComponent(
          label: strings.selectAll,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedTick02,
            size: IconSizes.small,
          ),
          semanticLabel: strings.selectAll,
          isSelected: _selectedFiles.files.length == widget.files.length,
          onTap: _selectedFiles.files.length == widget.files.length
              ? null
              : () => _selectedFiles.replaceSelection(widget.files.toSet()),
        ),
        SelectionSummaryChipComponent(
          label: strings.selectedPhotos(count: _selectedFiles.files.length),
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedCancel01,
            size: IconSizes.small,
          ),
          semanticLabel: strings.clearSelection,
          isSelected: _selectedFiles.files.isNotEmpty,
          onTap: _selectedFiles.files.isEmpty
              ? null
              : () => _selectedFiles.clearAll(fireEvent: false),
        ),
      ],
    );
  }

  Widget _buildGallery() {
    return GalleryFilesState(
      child: Gallery(
        initialFiles: widget.files,
        asyncLoader: (_, _, {limit, asc}) async =>
            FileLoadResult(widget.files, false),
        tagPrefix: 'person_share_gallery',
        selectedFiles: _selectedFiles,
        enableFileGrouping: false,
        inSelectionMode: true,
        disableSelection: _autoAdd,
        showSelectAll: false,
        disablePinnedGroupHeader: true,
        disableVerticalPaddingForScrollbar: true,
        footer: const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _shareLink() async {
    final person = widget.person;
    final albumName = person == null
        ? context.strings.unnamedPersonAlbumName(
            date: getDateAndMonthAndYear(DateTime.now()),
          )
        : person.data.name.trim();
    final dialog = createProgressDialog(context, context.strings.creatingLink);
    await dialog.show();
    final collections = CollectionsService.instance;
    Collection? album;
    try {
      album = await collections.createAlbum(albumName);
      await collections.addOrCopyToCollection(
        album.id,
        _filesToShare.map((file) => file.copyWith()).toList(),
        toCopy: false,
      );
      await collections.createShareUrl(album);
      if (_autoAdd) {
        await services.smartAlbumsService.addPeopleToSmartAlbum(album.id, [
          person!.remoteID,
        ]);
        unawaited(services.smartAlbumsService.syncSmartAlbums());
      }
      await dialog.hide();
      if (mounted) Navigator.of(context).pop(album);
    } catch (error, stack) {
      if (album != null) {
        try {
          await CollectionActions(
            collections,
          ).trashCollectionKeepingPhotos(album);
        } catch (cleanupError, cleanupStack) {
          _logger.severe(
            'Could not roll back person album ${album.id}',
            cleanupError,
            cleanupStack,
          );
          await dialog.hide();
          if (!mounted) return;
          await showErrorDialog(
            context,
            context.strings.personShareFailedTitle,
            context.strings.personShareRollbackFailed(name: album.displayName),
          );
          return;
        }
      }
      await dialog.hide();
      if (!mounted) return;
      if (error is SharingNotPermittedForFreeAccountsError) {
        final upgrade = await showBottomSheetComponent<bool>(
          context: context,
          builder: (context) => BottomSheetComponent(
            title: context.strings.subscribe,
            message: context.strings.subscribeToEnableSharing,
            closeTooltip: context.strings.close,
            actions: [
              ButtonComponent(
                label: context.strings.upgrade,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
        if (upgrade == true && mounted) {
          await routeToPage(context, getSubscriptionPage());
        }
      } else {
        _logger.severe('Could not share person', error, stack);
        await showErrorDialog(
          context,
          context.strings.personShareFailedTitle,
          context.strings.personShareFailedBody,
        );
      }
    }
  }

  Future<void> _shareFiles() async {
    if (!_canShareFiles) return;
    await share(context, _filesToShare, shareButtonKey: _rawShareButtonKey);
  }
}

class _SharePersonSheetBoundary extends StatefulWidget {
  const _SharePersonSheetBoundary({
    required this.position,
    required this.child,
  });

  final BoundaryPosition position;
  final Widget child;

  @override
  State<_SharePersonSheetBoundary> createState() =>
      _SharePersonSheetBoundaryState();
}

class _SharePersonSheetBoundaryState extends State<_SharePersonSheetBoundary>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return boundaryWidget(position: widget.position, child: widget.child);
  }
}
