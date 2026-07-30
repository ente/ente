import "dart:async";

import 'package:ente_components/ente_components.dart';
import "package:ente_events/event_bus.dart";
import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:locker/events/collections_updated_event.dart";
import 'package:locker/l10n/l10n.dart';
import "package:locker/models/selected_files.dart";
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/trash/models/trash_file.dart';
import 'package:locker/services/trash/trash_service.dart';
import "package:locker/ui/components/delete_confirmation_sheet.dart";
import 'package:locker/ui/components/item_list_view.dart';
import "package:locker/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";

class TrashPage extends StatefulWidget {
  final List<TrashFile> trashFiles;

  const TrashPage({super.key, required this.trashFiles});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashFile> _trashFiles = [];
  final SelectedFiles _selectedFiles = SelectedFiles();
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription<CollectionsUpdatedEvent> _trashUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _trashFiles = List.from(widget.trashFiles);
    _trashUpdateSubscription = Bus.instance
        .on<CollectionsUpdatedEvent>()
        .listen((_) => _refreshTrashFiles());
  }

  @override
  void dispose() {
    _trashUpdateSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshTrashFiles() async {
    final trashFiles = await TrashService.instance.getTrashFiles();
    if (!mounted) return;
    setState(() {
      _trashFiles = List.from(trashFiles);
    });
  }

  Future<void> _emptyTrash() async {
    if (_trashFiles.isEmpty) {
      showToast(context, context.l10n.trashIsEmpty);
      return;
    }

    final result = await showDeleteConfirmationSheet(
      context,
      title: context.l10n.emptyTrash,
      body: context.l10n.emptyTrashConfirmation,
      deleteButtonLabel: context.l10n.emptyTrash,
      illustration: LockerBottomSheetIllustration.collectionDelete,
    );

    if (result?.buttonResult.action == ButtonAction.first) {
      await _performEmptyTrash();
    }
  }

  Future<void> _performEmptyTrash() async {
    if (_trashFiles.isEmpty) {
      if (mounted) {
        showToast(context, context.l10n.trashIsEmpty);
      }
      return;
    }

    final dialog = mounted
        ? createProgressDialog(
            context,
            context.l10n.clearingTrash,
            isDismissible: false,
          )
        : null;
    await dialog?.show();
    try {
      await TrashService.instance.emptyTrash();
      await dialog?.hide();
      if (!mounted) return;
      _selectedFiles.clearAll();
      setState(() {
        _trashFiles.clear();
      });
      showToast(context, context.l10n.trashClearedSuccessfully);
      Navigator.of(context).pop();
    } catch (error) {
      await dialog?.hide();
      if (mounted) {
        await showLockerErrorSheet(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasTrashFiles = _trashFiles.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Stack(
        children: [
          AppBarComponent(
            title: context.l10n.trash,
            subtitle: hasTrashFiles
                ? context.l10n.items(_trashFiles.length)
                : null,
            actions: hasTrashFiles
                ? [
                    IconButtonComponent(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedDelete02,
                        color: colors.warning,
                      ),
                      variant: IconButtonComponentVariant.primary,
                      shouldSurfaceExecutionStates: false,
                      onTap: _emptyTrash,
                    ),
                  ]
                : const [],
            controller: _scrollController,
            slivers: _buildSlivers(context),
          ),
          FileSelectionOverlayBar(
            selectedFiles: _selectedFiles,
            files: _trashFiles.cast<EnteFile>(),
            scrollController: _scrollController,
            isTrashMode: true,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    if (_trashFiles.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _TrashEmptyState(title: context.l10n.yourTrashIsEmpty),
        ),
      ];
    }

    final safeBottomInset = MediaQuery.of(context).padding.bottom;
    final bottomPadding = safeBottomInset + 24.0;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16.0, 0, 16.0, bottomPadding),
        sliver: SliverToBoxAdapter(
          child: ItemListView(
            files: _trashFiles.cast<EnteFile>(),
            selectedFiles: _selectedFiles,
            selectionEnabled: true,
          ),
        ),
      ),
    ];
  }
}

class _TrashEmptyState extends StatelessWidget {
  const _TrashEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/empty_state.png', height: 112),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: TextStyles.large),
          ],
        ),
      ),
    );
  }
}
