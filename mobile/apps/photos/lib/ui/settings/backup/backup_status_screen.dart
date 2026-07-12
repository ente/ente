// ignore_for_file: public_member_api_docs, sort_constructors_first
import "dart:async";
import "dart:collection";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/backup_updated_event.dart";
import "package:photos/events/file_uploaded_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/backup/backup_item.dart";
import "package:photos/models/backup/backup_item_status.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/module/upload/service/file_uploader.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/settings/backup/backup_item_card.dart";

class BackupStatusScreen extends StatefulWidget {
  const BackupStatusScreen({super.key});

  @override
  State<BackupStatusScreen> createState() => _BackupStatusScreenState();
}

class _BackupStatusScreenState extends State<BackupStatusScreen> {
  final LinkedHashMap<String, BackupItem> _items = LinkedHashMap();
  List<BackupItem>? result;
  StreamSubscription? _fileUploadedSubscription;
  StreamSubscription? _backupUpdatedSubscription;

  @override
  void initState() {
    super.initState();

    _items.addAll(FileUploader.instance.allBackups);
    checkBackupUpdatedEvent();
    getAllFiles();
  }

  Future<void> getAllFiles() async {
    result = (await SearchService.instance.getAllFilesForSearch())
        .where((e) => e.uploadedFileID != null && e.isOwner)
        .map((e) {
          return BackupItem(
            status: BackupItemStatus.uploaded,
            file: e,
            collectionID: e.collectionID ?? 0,
            completer: null,
          );
        })
        .sorted(
          (a, b) => (b.file.uploadedFileID!).compareTo(a.file.uploadedFileID!),
        )
        .toList();
    _fileUploadedSubscription = Bus.instance.on<FileUploadedEvent>().listen((
      event,
    ) {
      result!.insert(
        0,
        BackupItem(
          status: BackupItemStatus.uploaded,
          file: event.file,
          collectionID: event.file.collectionID ?? 0,
          completer: null,
        ),
      );
      safeSetState();
    });
    safeSetState();
  }

  void checkBackupUpdatedEvent() {
    _backupUpdatedSubscription = Bus.instance.on<BackupUpdatedEvent>().listen((
      event,
    ) {
      for (final localID in event.removedLocalIDs) {
        _items.remove(localID);
      }
      _items.addAll(event.upserts);
      safeSetState();
    });
  }

  void safeSetState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _fileUploadedSubscription?.cancel();
    _backupUpdatedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<BackupItem> items = _items.values.toList().sorted(
      (a, b) => a.status.index.compareTo(b.status.index),
    );

    final allItems = <BackupItem>[
      ...items.where((element) => element.status != BackupItemStatus.uploaded),
      ...?result,
    ];

    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: AppLocalizations.of(context).backupStatus,
        slivers: [
          if (allItems.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyBackupStatus(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              sliver: SliverList.builder(
                itemBuilder: (context, index) {
                  return BackupItemCard(
                    item: allItems[index],
                    key: ValueKey(allItems[index].file.uploadedFileID),
                  );
                },
                itemCount: allItems.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBackupStatus extends StatelessWidget {
  const _EmptyBackupStatus();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: Spacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCloudUpload,
            color: colors.textLight,
            size: IconSizes.medium,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            AppLocalizations.of(context).backupStatusDescription,
            textAlign: TextAlign.center,
            style: TextStyles.large.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
