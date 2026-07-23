import "package:flutter/material.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/components/menu_section_title.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import "package:photos/ui/components/title_bar_widget.dart";
import "package:photos/ui/settings/pending_sync/path_info_storage_viewer.dart";

// Preview Video related items -> pv
// final String tempDir = Configuration.instance.getTempDirectory();
// final String prefix = "${tempDir}_${enteFile.uploadedFileID}_${newID("pv")}";
//
// Recovery Key -> ente-recovery-key.txt
// Configuration.instance.getTempDirectory() + "ente-recovery-key.txt",
//
// Encrypted files (upload), decrypted files (download) -> .encrypted & .decrypted
//   final String tempDir = Configuration.instance.getTempDirectory();
//   final String encryptedFilePath = "$tempDir${file.uploadedFileID}.encrypted";
//   final String decryptedFilePath = "$tempDir${file.uploadedFileID}.decrypted";
//
// Live photo compressed version -> .elp
// final livePhotoPath = tempPath + uniqueId + "_${file.generatedID}.elp";
//
// Explicit uploads -> _file.encrpyted & _thumb.encrypted
// final encryptedFilePath = multipartEntryExists
//     ? '$tempDirectory$existingMultipartEncFileName'
//     : '$tempDirectory$uploadTempFilePrefix${uniqueID}_file.encrypted';
// final encryptedThumbnailPath =
//     '$tempDirectory$uploadTempFilePrefix${uniqueID}_thumb.encrypted';

class PendingSyncInfoScreen extends StatefulWidget {
  const PendingSyncInfoScreen({super.key});

  @override
  State<PendingSyncInfoScreen> createState() => _PendingSyncInfoScreenState();
}

class _PendingSyncInfoScreenState extends State<PendingSyncInfoScreen> {
  final List<PathInfoStorageItem> paths = [];
  late bool internalUser;
  final int _refreshCounterKey = 0;

  @override
  void initState() {
    super.initState();
    internalUser = flagService.internalUser;
    addPath();
  }

  void addPath() async {
    final String tempDownload = Configuration.instance.getTempDirectory();
    paths.addAll([
      PathInfoStorageItem.name(
        tempDownload,
        "Encrypted Upload (File)",
        "_file.encrypted",
        allowCacheClear: false,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Encrypted Upload (Thumb)",
        "_thumb.encrypted",
        allowCacheClear: false,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Live photo",
        ".elp",
        allowCacheClear: false,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Encrypted Data",
        ".encrypted",
        allowCacheClear: false,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Decrypted Data",
        ".decrypted",
        allowCacheClear: false,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Partial Download",
        "_part",
        allowCacheClear: true,
      ),
      PathInfoStorageItem.name(
        tempDownload,
        "Video Preview",
        "pv",
        allowCacheClear: false,
      ),
    ]);
    if (mounted) {
      setState(() => {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            flexibleSpaceTitle: const TitleBarTitleWidget(title: "App Temp"),
            actionIcons: [
              IconButtonWidget(
                icon: Icons.close_outlined,
                iconButtonType: IconButtonType.secondary,
                onTap: () {
                  Navigator.pop(context);
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      children: [
                        MenuSectionTitle(
                          title: AppLocalizations.of(context).cachedData,
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(0),
                          physics: const ScrollPhysics(),
                          // to disable GridView's scrolling
                          itemBuilder: (context, index) {
                            final path = paths[index];
                            return PathInfoStorageViewer(
                              path,
                              removeTopRadius: index > 0,
                              removeBottomRadius: index < paths.length - 1,
                              enableDoubleTapClear: internalUser,
                              key: ValueKey("$index-$_refreshCounterKey"),
                            );
                          },
                          itemCount: paths.length,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ],
                ),
              );
            }, childCount: 1),
          ),
        ],
      ),
    );
  }
}
